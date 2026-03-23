# Stage 1: Build
FROM rust:1.93-slim AS builder
WORKDIR /app
COPY Cargo.toml ./
COPY src/ src/
RUN cargo build --release

# Stage 2: Runtime
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates curl && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/target/release/prism-sync-relay /usr/local/bin/prism-sync-relay
RUN mkdir -p /data
VOLUME /data
ENV DB_PATH=/data/relay.db
ENV PORT=8080
CMD ["prism-sync-relay"]
