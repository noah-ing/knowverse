# ENTERPRISE SECURITY DOCKERFILE
# Slim Debian base for better binary wheel compatibility

# Stage 1: Builder (compile dependencies)
FROM python:3.11-slim AS builder

# Set build args for optimization
ARG DEBIAN_FRONTEND=noninteractive
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PIP_NO_CACHE_DIR=1
ENV PIP_DISABLE_PIP_VERSION_CHECK=1

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev \
    libffi-dev \
    && rm -rf /var/lib/apt/lists/*

# Create virtual environment
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy and install Python dependencies
COPY requirements.txt .
RUN pip install --upgrade pip setuptools wheel && \
    pip install -r requirements.txt

# Stage 2: Production (lightweight runtime)
FROM python:3.11-slim AS production

# Enterprise environment variables
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app
ENV HAYSTACK_TELEMETRY_ENABLED=false
ENV PATH="/opt/venv/bin:$PATH"

# Install only runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    postgresql-client \
    curl \
    netcat-openbsd \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy virtual environment from builder
COPY --from=builder /opt/venv /opt/venv

# Set working directory
WORKDIR /app

# Create enterprise user with proper permissions
RUN groupadd -g 1000 haystack && \
    useradd -m -s /bin/bash -u 1000 -g haystack haystack && \
    mkdir -p /app/models /app/data /app/logs && \
    chown -R haystack:haystack /app && \
    chmod -R 755 /app

# Copy application code (do this last for better caching)
COPY --chown=haystack:haystack . .

# Create optimized entrypoint (Redis is optional - use host.docker.internal)
RUN echo '#!/bin/sh\n\
set -e\n\
echo "Waiting for PostgreSQL..."\n\
until pg_isready -h postgres -p 5432 -U postgres; do\n\
  sleep 1\n\
done\n\
echo "PostgreSQL ready! Starting Haystack..."\n\
exec "$@"' > /usr/local/bin/docker-entrypoint && \
    chmod +x /usr/local/bin/docker-entrypoint

# Switch to non-root user
USER haystack

# Expose port
EXPOSE 8000

# Optimized health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Set entrypoint and command
ENTRYPOINT ["docker-entrypoint"]
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
