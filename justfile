#!/usr/bin/env just --justfile
# vim:set ft=just ts=2 sts=4 sw=2 et:

# https://github.com/casey/just#settings
#set allow-duplicate-recipes
#set dotenv-load
#set export
#set positional-arguments
#set shell := ["bash", "-c"]

# Default recipe to run when just is called without arguments

# lists the tasks
@_list:
    just --list

help:
    @just --list

new:
    cargo new bunwarmer

# Build the project
build:
    cargo build --release && cp target/release/bunwarmer bin/bunwarmer

docker-build:
    docker build -t bunwarmer .

# Run tests
test:
    cargo test

# Run clippy for linting
lint:
    cargo clippy -- -D warnings

# Format code
format:
    cargo fmt

# Check formatting
check-format:
    cargo fmt -- --check

# Clean build artifacts
clean:
    cargo clean
    test -f bin/bunwarmer && rm -f bin/bunwarmer

# Adaptive Block Size: If the user doesn't specify a block size (or specifies 0),
# the program will choose a block size based on the volume size. This is a simplified
# heuristic and could be expanded to consider the actual EBS volume type.
#
# This would use a 256 KiB block size, which is optimal for SSD volumes.
# sudo ./bunwarmer --devices /dev/nvme0n1:gp3 --workers 8 --blocksize 0 --benchmark --max-retries 5
# cargo run --release -- --devices /dev/nvme0n1:gp3,/dev/nvme1n1:gp3 --workers 8 --blocksize 0 --benchmark --max-retries 5
# cargo run --release -- --devices /dev/nvme0n1,/dev/nvme1n1 --workers 8 --blocksize 0 --benchmark --max-retries 5 --aws-access-key-id YOUR_ACCESS_KEY --aws-secret-access-key YOUR_SECRET_KEY --aws-region us-east-1
# sudo ./bunwarmer --devices /dev/nvme0n1:gp3 --workers 8 --blocksize 262144 --benchmark --max-retries 5

# Run on Linux (example)
run-linux:
  bin/bunwarmer --devices /dev/nvme0n1:gp3 --workers 8 --blocksize 0 --benchmark

# Run on macOS (example)
run-macos:
  bin/bunwarmer --devices /dev/rdisk5:gp3 --workers 8 --blocksize 0 --benchmark --use-mmap

# Note: The --privileged flag is used because your tool needs direct access to devices.
# Be cautious with this in production environments.
docker-run-linux:
  docker run --privileged bunwarmer --devices /dev/nvme0n1:gp3 --workers 8 --blocksize 0 --benchmark

# Full check: format, lint, and test
check: format lint test
  @echo "All checks passed!"

# Build and run (for Linux)
build-and-run-linux: build
  just run-linux

# Build and run (for macOS)
build-and-run-macos: build
  just run-macos

docker-build-and-run-linux: docker-build
  just docker-run-linux

# Generate documentation
doc:
  cargo doc --no-deps --open

# Update dependencies
update:
  cargo update

# Show outdated dependencies
outdated:
  cargo outdated

# Security audit
audit:
  cargo audit

# Continuous integration tasks
ci: check-format lint test audit
  @echo "CI tasks completed successfully!"
