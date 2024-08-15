#!/bin/bash

#bins=(cargo)

# macOS and install rust
"$(brew --prefix)"/bin/brew update
"$(brew --prefix)"/bin/brew install git git-lfs fswatch just rustup-init
rustup-init -y --no-modify-path --default-toolchain=stable --profile=minimal
#source "${HOME}/.cargo/env"
#CARGO_HOME=$HOME/.cargo

# Build
#cargo build --release

#target/release/bunwarmer src/main.rs

## Linux
#cargo build --release --target x86_64-pc-windows-gnu
#cargo build --release --target x86_64-unknown-linux-musl

## macOS
#cargo build --release --target aaarch64-apple-darwin
#cargo build --release --target x86_64-apple-darwin

