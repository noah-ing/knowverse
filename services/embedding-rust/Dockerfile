# Knowverse Embedding Service - Rust ONNX Runtime
# Multi-stage build for minimal production image

# Build stage
FROM rust:1.83-bookworm AS builder

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy Cargo files for dependency caching
COPY Cargo.toml Cargo.lock* ./

# Create dummy src to build dependencies
RUN mkdir src && echo "fn main() {}" > src/main.rs
RUN cargo build --release || true
RUN rm -rf src

# Copy actual source code
COPY src ./src

# Build the application
RUN cargo build --release

# Runtime stage
FROM debian:bookworm-slim

WORKDIR /app

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -r -s /bin/false embedding

# Copy binary from builder
COPY --from=builder /app/target/release/knowverse-embedding /app/knowverse-embedding

# Create models directory
RUN mkdir -p /app/models && chown -R embedding:embedding /app

USER embedding

# Environment variables
ENV EMBEDDING_HOST=0.0.0.0
ENV EMBEDDING_PORT=8001
ENV MODEL_PATH=/app/models
ENV DEFAULT_MODEL=all-MiniLM-L6-v2
ENV CACHE_SIZE_MB=512
ENV MAX_BATCH_SIZE=64
ENV RUST_LOG=info

EXPOSE 8001

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8001/health || exit 1

CMD ["/app/knowverse-embedding"]
