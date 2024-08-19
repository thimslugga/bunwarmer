# syntax=docker/dockerfile:1

# We use a multi-stage build setup.
# See: https://docs.docker.com/build/building/multi-stage/

# https://hub.docker.com/_/rust
FROM docker.io/rust:1.80 as builder

ARG PROJECT_VERSION

#LABEL "name"="Automate build of bunwarmer"
#LABEL "version"="0.1.0"

# Create a new empty shell project
RUN USER=root cargo new --bin bunwarmer

WORKDIR /bunwarmer

# Copy our manifests
COPY ./Cargo.lock ./Cargo.lock
COPY ./Cargo.toml ./Cargo.toml
COPY ./deny.toml ./deny.toml

# Copy the source code
COPY ./src ./src

# Build only the dependencies to cache them
#RUN cargo build --release
#RUN rm src/*.rs

# Build for release
#RUN rm ./target/release/deps/bunwarmer*
RUN cargo build --release

# Final base
FROM docker.io/debian:bookworm-slim

#FROM scratch
#WORKDIR /root/

# Install libssl
#RUN apt-get update \
  #&& apt-get install -qqy libssl1.1 \
  #&& rm -rf /var/lib/apt/lists/*

# Copy the build artifact from the builder stage
COPY --from=builder /bunwarmer/target/release/bunwarmer .

# Set the startup command
ENTRYPOINT ["./bunwarmer"]
