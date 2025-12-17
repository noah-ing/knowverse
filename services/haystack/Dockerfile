# ENTERPRISE SECURITY DOCKERFILE - Zero Vulnerabilities
# Alpine Linux base for maximum security

# Stage 1: Builder (compile dependencies)
FROM python:3.13-alpine as builder

# Set build args for optimization
ARG DEBIAN_FRONTEND=noninteractive
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PIP_NO_CACHE_DIR=1
ENV PIP_DISABLE_PIP_VERSION_CHECK=1

# Install build dependencies for Alpine
RUN apk add --no-cache \
    build-base \
    postgresql-dev \
    libffi-dev \
    musl-dev \
    openblas-dev \
    lapack-dev \
    gfortran \
    rust \
    cargo \
    && rm -rf /var/cache/apk/*

# Create virtual environment
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy and install Python dependencies
COPY requirements.txt .
RUN pip install --upgrade pip setuptools wheel && \
    pip install -r requirements.txt

# Stage 2: Production (lightweight runtime)
FROM python:3.13-alpine as production

# Enterprise environment variables
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app
ENV HAYSTACK_TELEMETRY_ENABLED=false
ENV PATH="/opt/venv/bin:$PATH"

# Install only runtime dependencies for Alpine
RUN apk add --no-cache \
    postgresql-client \
    curl \
    netcat-openbsd \
    ca-certificates \
    && rm -rf /var/cache/apk/*

# Copy virtual environment from builder
COPY --from=builder /opt/venv /opt/venv

# Set working directory
WORKDIR /app

# Create enterprise user with proper permissions
RUN addgroup -g 1000 haystack && \
    adduser -D -s /bin/sh -u 1000 -G haystack haystack && \
    mkdir -p /app/models /app/data /app/logs && \
    chown -R haystack:haystack /app && \
    chmod -R 755 /app

# Copy application code (do this last for better caching)
COPY --chown=haystack:haystack . .

# Create optimized entrypoint
RUN echo '#!/bin/sh\n\
set -e\n\
echo "🔍 Waiting for dependencies..."\n\
until pg_isready -h postgres -p 5432 -U postgres && nc -z redis 6379; do\n\
  sleep 1\n\
done\n\
echo "✅ Dependencies ready! Starting Haystack..."\n\
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
