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
    gosu \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN groupadd -r zeroclaw && useradd -r -g zeroclaw -m -d /home/zeroclaw zeroclaw

# Copy binary from build stage
COPY --from=builder /build/target/release/zeroclaw /usr/local/bin/zeroclaw

# Create data directories
RUN mkdir -p /home/zeroclaw/.zeroclaw/workspace \
    && chown -R zeroclaw:zeroclaw /home/zeroclaw/.zeroclaw

# Entrypoint: fix bind-mount permissions, then drop to zeroclaw user
RUN printf '#!/bin/sh\nset -e\nchown -R zeroclaw:zeroclaw /home/zeroclaw/.zeroclaw 2>/dev/null || true\nexec gosu zeroclaw tini -- "$@"\n' \
    > /usr/local/bin/entrypoint.sh \
    && chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /home/zeroclaw

HEALTHCHECK --interval=60s --timeout=10s --start-period=30s --retries=3 \
    CMD gosu zeroclaw zeroclaw status || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["zeroclaw", "daemon"]
