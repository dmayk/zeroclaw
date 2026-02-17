# =============================================================================
# Zeroclaw — Multi-Stage Docker Build (from local source)
# =============================================================================
# Expects the zeroclaw repo as build context (i.e. the cloned repo directory).
# Usage:
#   docker build -t zeroclaw:latest -f Dockerfile repo/
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
    gosu \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN groupadd -r zeroclaw && useradd -r -g zeroclaw -m -d /home/zeroclaw zeroclaw

# Copy binary from build stage
COPY --from=builder /build/target/release/zeroclaw /usr/local/bin/zeroclaw

# Create data directories
RUN mkdir -p /home/zeroclaw/.zeroclaw/workspace \
    && chown -R zeroclaw:zeroclaw /home/zeroclaw/.zeroclaw

# Create entrypoint that fixes bind-mount permissions then drops to zeroclaw user
RUN printf '#!/bin/sh\nset -e\nchown -R zeroclaw:zeroclaw /home/zeroclaw/.zeroclaw 2>/dev/null || true\nexec gosu zeroclaw tini -- "$@"\n' \
    > /usr/local/bin/entrypoint.sh \
    && chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /home/zeroclaw

# Health check
HEALTHCHECK --interval=60s --timeout=10s --start-period=30s --retries=3 \
    CMD gosu zeroclaw zeroclaw status || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["zeroclaw", "daemon"]
