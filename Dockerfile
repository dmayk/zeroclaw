# =============================================================================
# Zeroclaw — Multi-Stage Docker Build
# =============================================================================
# Self-contained: clones the repo and builds from source.
# No local repo checkout needed — just build this Dockerfile.
#
# Usage:
#   docker build -t zeroclaw:latest .
#   docker build -t zeroclaw:latest --build-arg ZEROCLAW_VERSION=v0.5.0 .
# =============================================================================

# --- Stage 1: Build ---
FROM rust:1.83-bookworm AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

ARG ZEROCLAW_VERSION=main
RUN git clone --depth 1 --branch ${ZEROCLAW_VERSION} \
    https://github.com/zeroclaw-labs/zeroclaw.git .

RUN cargo build --release --locked \
    && strip target/release/zeroclaw

# --- Stage 2: Runtime ---
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libssl3 \
    tini \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/target/release/zeroclaw /usr/local/bin/zeroclaw

RUN mkdir -p /root/.zeroclaw/workspace

WORKDIR /root

ENTRYPOINT ["tini", "--"]
CMD ["zeroclaw", "daemon"]
