#!/usr/bin/env just --justfile
# vim:set ft=just ts=2 sts=4 sw=2 et:

# justfile requires https://github.com/casey/just
# settings: https://github.com/casey/just#settings
set allow-duplicate-recipes := false
# Load environment variables from `.env` file.
set dotenv-load := true
set export := false
#set positional-arguments
#set shell := ["bash", "-euo", "pipefail", "-c"]
set shell := ["bash", "-c"]

timestamp := `date +%s`
semver := env_var('PROJECT_VERSION')
commit := `git show -s --format=%h`
version := semver + "+" + commit

# Default recipe to run when just is called without arguments

# call 'just' to get help
#default:
#  @just --list --justfile {{justfile()}}

# lists the tasks and variables in the justfile
@_list:
  just --justfile ./justfile --list --unsorted
  echo ""
  echo "Available variables:"
  just --evaluate | sed 's/^/    /'
  echo ""
  echo "Override variables using 'just key=value ...' (also ALL_UPPERCASE ones)"

help:
  @just --justfile ./justfile --list

# Evaluate and return all just variables
evaluate:
  @just --evaluate

# Return system information (e.g. os, architecture, etc)
system-info:
  @echo "architecture: {{arch()}}"
  @echo "os: {{os()}}"
  @echo "os family: {{os_family()}}"

# Run clippy for linting
alias lint := lint-rust
lint-rust:
  @echo "Linting source code .."
  cargo clippy -- -D warnings

# Run `cargo fmt` to format source code
format:
  @echo "Formatting source code .."
  cargo fmt

# Check formatting
check-format:
  cargo fmt -- --check

# Full check: format, lint, and test
check: format lint-rust test
  @echo "All checks passed!"

# Continuous integration tasks
ci: check-format lint-rust test audit
  @echo "CI tasks completed successfully!"

# Security audit
audit:
  cargo audit

# Clean build artifacts
clean:
  cargo clean
  #test -f bin/bunwarmer && rm -f bin/bunwarmer

# Run tests
test:
  cargo test

# Generate documentation
doc:
  cargo doc --no-deps --open

# Update dependencies
update:
  cargo update

# Show outdated dependencies
outdated:
  cargo outdated

fetch:
	cargo run --release -- fetch

analyze:
	cargo run --release -- analyze

new:
  cargo new bunwarmer

# Build the project
build:
  cargo build --release && cp target/release/bunwarmer bin/bunwarmer

# Build and run (for Linux)
build-and-run-linux: build
  just run-linux

# Run on Linux (example)
run-linux:
  bin/bunwarmer --devices /dev/nvme0n1:gp3 --workers 8 --blocksize 0 --benchmark

# Build and run (for macOS)
build-and-run-macos: build
  just run-macos

# Run on macOS (example)
run-macos:
  bin/bunwarmer --devices /dev/rdisk5:gp3 --workers 8 --blocksize 0 --benchmark --use-mmap

docker-image-create:
  @echo "Creating a docker image ..."
  #@PROJECT_VERSION={{version}} ./make_image.sh
  docker build -f Dockerfile -t localhost/bunwarmer:0.1.0 .

docker-image-run:
  @echo "Running container from docker image ..."
  docker run --rm -it --rm localhost/bunwarmer:0.1.0
  #docker run --pull always --rm -it --rm -v $(pwd):/root localhost/bunwarmer:0.1.0

#docker-run-help:
#  docker run -ti --rm localhost/bunwarmer:0.1.0 --help

# Note: The --privileged flag is used because your tool needs direct access to devices.
# Be cautious with this in production environments.
#docker-image-run-privileged:
#  docker run --privileged bunwarmer --devices /dev/nvme0n1:gp3 --workers 8 --blocksize 0 --benchmark


### docker-just ###

DOCKER_CMD := "docker"
BUILDER_NAME := "docker-just"
BUILDER_PLATFORM := "linux/amd64"

docker-builder-create:
  {{ DOCKER_CMD }} buildx create \
    --driver docker-container \
    --name {{ BUILDER_NAME }} \
    --platform {{ BUILDER_PLATFORM }} \
    || true

docker-builder-remove:
  {{ DOCKER_CMD }}  buildx rm --keep-state {{ BUILDER_NAME }}

docker-bake-image *OPTIONS: docker-builder-create && docker-builder-remove
  {{ DOCKER_CMD }} buildx bake \
    --builder {{ BUILDER_NAME }} \
    --pull \
    {{ OPTIONS }}

docker-bake-push: (docker-bake-image "--push")
