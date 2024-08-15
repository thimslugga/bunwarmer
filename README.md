# Bunwarmer

## Background

Pre-warming aka hydrating an EBS (Elastic Block Store) volume is done to improve the initial perfomance. It ensures that all blocks are readily available on the EBS volume, which results in consistent performance.

When you create a new EBS volume or restore a volume from a snapshot, the blocks of data are lazy loaded from Amazon S3 to the volume. This means that the first time you access a block of data, there may be a bit of latency as it needs to be pulled from S3. For very large volumes, the impact of lazy loading can be more pronounced, making pre-warming particularly important.

Without pre-warming / hydrating, your workload may experience the following on the initial access of the data:

- Higher Latency
- Lower IOPS (Input/Output Operations Per Second)

When is pre-warming important:

- For applications where performance is critical from the moment they start, pre-warming ensures they have full performance capabilities immediately.
- In scenarios where you need to guarantee a certain level of performance (e.g., for benchmarking or in production environments), pre-warming helps ensure predictable performance.

There are different methods to pre-warm EBS volumes, depending on whether it's a new volume, a restored snapshot, or if you're using certain EBS volume types. The process typically involves reading all the blocks on the volume, which can be done using tools like dd or fio.

## Elastic Block Storage (EBS) Characteristics

### I/O Size

Different EBS volume types have different performance characteristics:

- General Purpose SSD (gp2/gp3): 16 KB I/O size
- Provisioned IOPS SSD (io1/io2): 16 KB I/O size
- Throughput Optimized HDD (st1): 1 MB I/O size
- Cold HDD (sc1): 1 MB I/O size

The maximum I/O size limits for Amazon EBS volumes:

- 256 KiB for SSD volumes
- 1 MiB for HDD volumes

### Block Size

A block size of 256 KiB (262,144 bytes) is often a good choice. It's the maximum I/O size for SSD volumes and can provide a good balance of throughput and IOPS.

The block size should be chosen so that it doesn't put undue pressure on system memory. For best performance, the block size should also be aligned with the underlying storage system. 4K alignment is common.

- Larger block sizes can improve throughput but may reduce IOPS.
- Smaller block sizes can increase IOPS but may reduce overall throughput.
