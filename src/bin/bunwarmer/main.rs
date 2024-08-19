use std::fs::File;
use std::path::Path;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use clap::Parser;
use tokio::sync::mpsc;
use tokio::time::sleep;

use indicatif::{MultiProgress, ProgressBar, ProgressStyle};

#[cfg(target_os = "linux")]
use nix::fcntl::{self, OFlag};
#[cfg(target_os = "linux")]
use nix::sys::stat::Mode;
#[cfg(target_os = "linux")]
use nix::unistd;

#[cfg(target_os = "macos")]
use libc::{c_int, c_void, mmap, munmap, size_t, F_NOCACHE, MAP_PRIVATE, PROT_READ};
#[cfg(target_os = "macos")]
use std::io::{Read, Seek, SeekFrom};
#[cfg(target_os = "macos")]
use std::os::unix::io::AsRawFd;

#[derive(Parser, Debug)]
#[clap(author, version, about, long_about = None)]
struct Args {
    /// Paths to the EBS volume devices and their types (comma-separated, format: path:type)
    /// Example: /dev/nvme1n1:gp2,/dev/nvme2n1:io1
    #[clap(short, long)]
    devices: String,

    /// Number of concurrent workers per device
    #[clap(short, long, default_value_t = 4)]
    workers: usize,

    /// Block size in bytes (0 for adaptive)
    #[clap(short, long, default_value_t = 0)]
    blocksize: u64,

    /// Enable benchmarking mode
    #[clap(short, long)]
    benchmark: bool,

    /// Maximum number of retries for failed reads
    #[clap(long, default_value_t = 3)]
    max_retries: u32,

    /// Use memory-mapped I/O (macOS only)
    #[cfg(target_os = "macos")]
    #[clap(long)]
    use_mmap: bool,
}

// EBS volume types
#[derive(Debug, Clone)]
enum EbsVolumeType {
    Gp2,
    Gp3,
    Io1,
    Io2,
    St1,
    Sc1,
    Unknown,
}

impl std::str::FromStr for EbsVolumeType {
    type Err = String;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "gp2" => Ok(EbsVolumeType::Gp2),
            "gp3" => Ok(EbsVolumeType::Gp3),
            "io1" => Ok(EbsVolumeType::Io1),
            "io2" => Ok(EbsVolumeType::Io2),
            "st1" => Ok(EbsVolumeType::St1),
            "sc1" => Ok(EbsVolumeType::Sc1),
            _ => Ok(EbsVolumeType::Unknown),
        }
    }
}

// Determine the optimal block size based on the specified EBS volume type
fn determine_block_size(file: &File, volume_type: &EbsVolumeType) -> u64 {
    match volume_type {
        EbsVolumeType::Gp2 | EbsVolumeType::Gp3 | EbsVolumeType::Io1 | EbsVolumeType::Io2 => {
            262_144
        } // 256 KB
        EbsVolumeType::St1 | EbsVolumeType::Sc1 => 1_048_576, // 1 MB
        EbsVolumeType::Unknown => {
            let size = file.metadata().unwrap().len();
            if size > 1_000_000_000_000 {
                1_048_576
            } else {
                262_144
            }
        }
    }
}

// Linux specific functions
#[cfg(target_os = "linux")]
fn read_chunk(fd: i32, buffer: &mut [u8], offset: u64) -> std::io::Result<usize> {
    unistd::lseek(fd, offset as i64, unistd::Whence::SeekSet)?;
    let n = unistd::read(fd, buffer)?;
    Ok(n)
}

// macOS specific
#[cfg(target_os = "macos")]
fn set_nocache(file: &File) -> std::io::Result<()> {
    let fd = file.as_raw_fd();
    if unsafe { libc::fcntl(fd, F_NOCACHE, 1) } == -1 {
        return Err(std::io::Error::last_os_error());
    }
    Ok(())
}

#[cfg(target_os = "macos")]
fn read_chunk(file: &mut File, buffer: &mut [u8], offset: u64) -> std::io::Result<usize> {
    file.seek(SeekFrom::Start(offset))?;
    let fd = file.as_raw_fd();
    let buf_ptr = buffer.as_mut_ptr() as *mut c_void;
    let count = buffer.len() as size_t;
    let bytes_read = unsafe { libc::pread(fd, buf_ptr, count, offset as i64) };
    if bytes_read < 0 {
        Err(std::io::Error::last_os_error())
    } else {
        Ok(bytes_read as usize)
    }
}

#[cfg(target_os = "macos")]
fn prewarm_mmap(file: &File, file_size: u64) -> std::io::Result<()> {
    let fd = file.as_raw_fd();
    let addr = unsafe {
        mmap(
            std::ptr::null_mut(),
            file_size as usize,
            PROT_READ,
            MAP_PRIVATE,
            fd,
            0,
        )
    };
    if addr == libc::MAP_FAILED {
        return Err(std::io::Error::last_os_error());
    }

    // Read through the mapped memory
    let slice = unsafe { std::slice::from_raw_parts(addr as *const u8, file_size as usize) };
    for chunk in slice.chunks(4096) {
        std::hint::black_box(chunk[0]); // Prevent optimization
    }

    unsafe { munmap(addr, file_size as usize) };
    Ok(())
}

// Pre-warm the block device(s) by reading all blocks sequentially
async fn prewarm_device(
    device_path: String,
    volume_type: EbsVolumeType,
    num_workers: usize,
    block_size: u64,
    max_retries: u32,
    progress_bar: ProgressBar,
    #[cfg(target_os = "macos")] use_mmap: bool,
) -> std::io::Result<(String, u64, Duration)> {
    println!(
        "Pre-warming block device: {} (Type: {:?})",
        device_path, volume_type
    );

    let file = File::open(&device_path)?;
    let file_size = file.metadata()?.len();

    // macOS specific, use memory-mapped I/O
    #[cfg(target_os = "macos")]
    if use_mmap {
        println!("Using memory-mapped I/O for {}", device_path);
        let start_time = Instant::now();
        prewarm_mmap(&file, file_size)?;
        let duration = start_time.elapsed();
        progress_bar.finish_with_message("Complete (mmap)");
        return Ok((device_path, file_size, duration));
    }

    // macOS specific, disable caching on macOS, like Direct IO i.e. O_DIRECT on Linux
    #[cfg(target_os = "macos")]
    set_nocache(&file)?;

    let actual_block_size = if block_size == 0 {
        determine_block_size(&file, &volume_type)
    } else {
        block_size
    };

    println!(
        "Device: {} | Size: {} bytes | Block size: {} bytes",
        device_path, file_size, actual_block_size
    );

    let bytes_read = Arc::new(AtomicU64::new(0));
    let (tx, mut rx) = mpsc::channel(num_workers);

    let start_time = Instant::now();

    for i in 0..num_workers {
        let tx = tx.clone();
        let bytes_read = Arc::clone(&bytes_read);
        let device_path = device_path.clone();
        let progress_bar = progress_bar.clone();

        tokio::spawn(async move {
            #[cfg(target_os = "linux")]
            let fd = match fcntl::open(
                Path::new(&device_path),
                OFlag::O_RDONLY | OFlag::O_DIRECT,
                Mode::empty(),
            ) {
                Ok(fd) => fd,
                Err(e) => {
                    eprintln!("Error opening block device {}: {}", device_path, e);
                    return;
                }
            };

            // macOS specific file handling
            #[cfg(target_os = "macos")]
            let mut file = match File::open(&device_path) {
                Ok(file) => file,
                Err(e) => {
                    eprintln!("Error opening block device {}: {}", device_path, e);
                    return;
                }
            };

            let mut buffer = vec![0; actual_block_size as usize];
            let mut worker_bytes_read = 0u64;

            for offset in (i as u64 * actual_block_size..file_size)
                .step_by(num_workers * actual_block_size as usize)
            {
                let mut retries = 0;
                loop {
                    #[cfg(target_os = "linux")]
                    let result = read_chunk(fd, &mut buffer, offset);

                    // macOS-specific file handling
                    #[cfg(target_os = "macos")]
                    let result = read_chunk(&mut file, &mut buffer, offset);

                    match result {
                        Ok(n) if n > 0 => {
                            worker_bytes_read += n as u64;
                            let new_bytes =
                                bytes_read.fetch_add(n as u64, Ordering::Relaxed) + n as u64;
                            progress_bar.set_position(new_bytes);
                            break;
                        }
                        Ok(_) => break, // End of file
                        Err(e) => {
                            if retries >= max_retries {
                                eprintln!("Error reading at offset {}: {}", offset, e);
                                break;
                            }
                            retries += 1;
                            sleep(Duration::from_millis(100)).await;
                        }
                    }
                }
            }

            // Linux specific handling
            #[cfg(target_os = "linux")]
            let _ = unistd::close(fd); // Ignore potential close errors

            let _ = tx.send(worker_bytes_read).await; // Send worker's bytes read
        });
    }

    // Wait for all of the worker tasks to complete and sum up the bytes read
    let mut total_bytes_read = 0u64;
    for _ in 0..num_workers {
        if let Some(worker_bytes) = rx.recv().await {
            total_bytes_read += worker_bytes;
        }
    }

    let duration = start_time.elapsed();

    // Ensure the progress bar shows the correct total
    progress_bar.set_position(total_bytes_read);
    progress_bar.finish_with_message("Complete");

    Ok((device_path, total_bytes_read, duration))
}

// Main
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = Args::parse();

    let devices: Vec<(String, EbsVolumeType)> = args
        .devices
        .split(',')
        .map(|s| {
            let parts: Vec<&str> = s.split(':').collect();
            if parts.len() != 2 {
                Err(format!("Invalid block device specification: {}", s))
            } else {
                Ok((parts[0].to_string(), parts[1].parse()?))
            }
        })
        .collect::<Result<Vec<_>, String>>()?;

    let multi_progress = MultiProgress::new();

    let mut tasks = Vec::new();
    for (device, volume_type) in devices {
        let progress_bar = multi_progress.add(ProgressBar::new(0));
        let progress_style = ProgressStyle::default_bar()
            .template("[{elapsed_precise}] {bar:40.cyan/blue} {bytes}/{total_bytes} ({eta}) {msg}")
            .expect("Failed to create progress bar template")
            .progress_chars("=>-");

        progress_bar.set_style(progress_style);

        tasks.push(tokio::spawn(prewarm_device(
            device,
            volume_type,
            args.workers,
            args.blocksize,
            args.max_retries,
            progress_bar,
            #[cfg(target_os = "macos")]
            args.use_mmap,
        )));
    }

    let mut results = Vec::new();
    for task in tasks {
        match task.await {
            Ok(Ok((device, total_bytes, duration))) => {
                println!("Device {} completed: {} bytes read", device, total_bytes);
                results.push((device, total_bytes, duration));
            }
            Ok(Err(e)) => eprintln!("Error pre-warming block device: {}", e),
            Err(e) => eprintln!("Task panicked: {}", e),
        }
    }

    println!("\nPre-warming completed for all block devices.");
    if args.benchmark {
        for (device, total_bytes, duration) in results {
            let throughput = total_bytes as f64 / duration.as_secs_f64() / 1_000_000.0;
            println!(
                "Device: {} | Total bytes: {} | Time: {:.2} seconds | Throughput: {:.2} MB/s",
                device,
                total_bytes,
                duration.as_secs_f64(),
                throughput
            );
        }
    }
    Ok(())
}
