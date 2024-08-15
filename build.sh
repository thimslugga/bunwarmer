#!/bin/bash

#bins=(cargo)

# macOS and install rust
"$(brew --prefix)"/bin/brew update
"$(brew --prefix)"/bin/brew install git git-lfs fswatch
"$(brew --prefix)"/bin/brew install rustup-init
rustup-init -y --no-modify-path --default-toolchain=stable --profile=minimal
#source "${HOME}/.cargo/env"
#CARGO_HOME=$HOME/.cargo

# Build
cargo build --release

#target/release/bunwarmer src/main.rs
