#!/bin/bash

function install_rustup() {
  echo "Installing rustup-init..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
  source "${HOME}"/.cargo/env
}

function rustup_init_toolchain() {
  if ! command -v rustup-init &>/dev/null; then
    echo "rustup-init could not be found."
  else
    echo "rustup-init is installed, setting up default toolchain..."
    rustup-init -y --no-modify-path --default-toolchain=stable --profile=minimal
  fi
}

# Install cargo
function cargo_check() {
  if ! command -v cargo &>/dev/null; then
    echo "cargo could not be found."
    #install_rustup
  else
    echo "cargo is already installed."
  fi
}

# macOS install homebrew if not found
function install_homebrew_macos() {
  if ! command -v brew &>/dev/null; then
    echo "Homebrew could not be found. Aborting."
    return 1
    #echo "Installing brew..."
    #/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  else
    echo "Homebrew is already installed. Let's update it ..."
    "$(brew --prefix)"/bin/brew update
  fi
}

# macOS
function build_dependecies_check_macos() {

  install_homebrew_macos

  local required_commands missing_packages
  required_commands=(git git-lfs fswatch just rustup-init earthly)
  missing_packages=()

  for command in "${required_commands[@]}"; do
    if ! command -v "${command}" &>/dev/null; then
      missing_packages+=("${command}")
      echo "Command '${command}' not found. Added to installation list."
    else
      echo "Command '${command}' was found."
    fi
  done

  if [[ ${#missing_packages[@]} -gt 0 ]]; then
    echo "Installing missing packages..."
    "$(brew --prefix)"/bin/brew install "${missing_packages[@]}"
  else
    echo "All required packages are installed."
  fi
}

# #target/release/bunwarmer src/main.rs

# Build on Linux
function cargo_build_linux() {
  cargo build --release --target x86_64-pc-windows-gnu
  #cargo build --release --target x86_64-unknown-linux-musl
}

# Build on macOS
function cargo_build_macos() {
  cargo build --release --target aarch64-apple-darwin
  #cargo build --release --target x86_64-apple-darwin
}

case "$(uname -s)" in
Darwin)
  # macOS
  echo "Detected: macOS"
  cargo_build_macos
  ;;
Linux)
  # GNU/Linux
  echo "Detected: Linux"
  cargo_build_linux
  ;;
CYGWIN* | MINGW32* | MSYS* | MINGW*)
  # Lightweight shell and GNU utilities compiled for Windows (part of MinGW)
  echo "Detected: Windows"
  echo "Unsupported OS."
  ;;
*)
  # Unknown.
  echo "Unknown OS."
  ;;
esac
