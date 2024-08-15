# https://hub.docker.com/_/rust
FROM rust:1.80 as builder

# Create a new empty shell project
RUN USER=root cargo new --bin bunwarmer

WORKDIR /bunwarmer

# Copy our manifests
COPY ./Cargo.lock ./Cargo.lock
COPY ./Cargo.toml ./Cargo.toml

# Build only the dependencies to cache them
RUN cargo build --release
RUN rm src/*.rs

# Copy the source code
COPY ./src ./src

# Build for release
RUN rm ./target/release/deps/bunwarmer*
RUN cargo build --release


# Final base
FROM debian:bullseye-slim

# Install libssl
RUN apt-get update \
  #&& apt-get install -y libssl1.1 \
  && rm -rf /var/lib/apt/lists/*

# Copy the build artifact from the builder stage
COPY --from=builder /bunwarmer/target/release/bunwarmer .

# Set the startup command
ENTRYPOINT ["./bunwarmer"]
