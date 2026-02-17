# =============================================================================
# Zeroclaw — Multi-Stage Docker Build (from local source)
# =============================================================================
# Expects the zeroclaw repo as build context (i.e. the cloned repo directory).
# Usage:
#   docker build -t zeroclaw:latest /path/to/zeroclaw-repo
# =============================================================================

# --- Stage 1: Build ---
FROM rust:1.83-bookworm AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Copy repo source into the build container
COPY . .

# Build release binary
RUN cargo build --release --locked \
    && strip target/release/zeroclaw

# --- Stage 2: Runtime ---
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libssl3 \
    tini \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN groupadd -r zeroclaw && useradd -r -g zeroclaw -m -d /home/zeroclaw zeroclaw

# Copy binary from build stage
COPY --from=builder /build/target/release/zeroclaw /usr/local/bin/zeroclaw

# Create data directories
RUN mkdir -p /home/zeroclaw/.zeroclaw/workspace \
    && chown -R zeroclaw:zeroclaw /home/zeroclaw/.zeroclaw

USER zeroclaw
WORKDIR /home/zeroclaw

# Health check
HEALTHCHECK --interval=60s --timeout=10s --start-period=30s --retries=3 \
    CMD zeroclaw status || exit 1

# Use tini as init system for proper signal handling
ENTRYPOINT ["tini", "--"]

# Default: run as daemon for 24/7 operation
CMD ["zeroclaw", "daemon"]
