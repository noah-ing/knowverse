# Knowverse Document Processor - WASM-Sandboxed Parsing
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
RUN mkdir -p src/extractors && \
    echo "fn main() {}" > src/main.rs && \
    echo "pub mod pdf; pub mod excel; pub mod docx; pub mod csv; pub mod text; pub mod chunker;" > src/extractors/mod.rs && \
    touch src/extractors/pdf.rs src/extractors/excel.rs src/extractors/docx.rs src/extractors/csv.rs src/extractors/text.rs src/extractors/chunker.rs
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
RUN useradd -r -s /bin/false docproc

# Copy binary from builder
COPY --from=builder /app/target/release/knowverse-docproc /app/knowverse-docproc

# Create temp directory
RUN mkdir -p /tmp/docproc && chown -R docproc:docproc /app /tmp/docproc

USER docproc

# Environment variables
ENV DOCPROC_HOST=0.0.0.0
ENV DOCPROC_PORT=8002
ENV MAX_FILE_SIZE_MB=100
ENV TEMP_DIR=/tmp/docproc
ENV SANDBOX_ENABLED=true
ENV TIMEOUT_SECONDS=60
ENV DEFAULT_CHUNK_SIZE=512
ENV DEFAULT_CHUNK_OVERLAP=64
ENV RUST_LOG=info

EXPOSE 8002

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8002/health || exit 1

CMD ["/app/knowverse-docproc"]
