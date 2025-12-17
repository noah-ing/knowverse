# Knowverse Enterprise Docker Development Environment

## Overview

This document provides instructions for setting up the complete Knowverse development environment using Docker. This enterprise-grade solution eliminates Windows compatibility issues and provides full feature parity across all platforms.

## Architecture

### Multi-Service Container Stack

- **Rails 8 Application**: Main web application with full SolidQueue support
- **PostgreSQL 14+ with pgvector**: Vector database with automatic extension setup
- **Redis 7+**: Caching and session management with persistence
- **Python Haystack Service**: FastAPI-based AI/RAG service with 18+ endpoints
- **Background Workers**: SolidQueue for job processing
- **Asset Watchers**: Tailwind CSS compilation

### Key Benefits

- ✅ **Full Feature Parity**: All background jobs, caching, and AI features work
- ✅ **Production Alignment**: Development environment matches production exactly  
- ✅ **Cross-Platform**: Works identically on Windows, macOS, and Linux
- ✅ **No Platform Code**: Eliminates 500+ lines of Windows workarounds
- ✅ **Hot Reload**: Live code changes without rebuilds
- ✅ **Enterprise Standards**: Industry best practices for containerized development

## Prerequisites

- Docker Desktop 4.0+ with Docker Compose V2
- WSL2 enabled (Windows only)
- At least 8GB RAM available for containers
- Git for version control

## Quick Start

### 1. Clone and Setup

```bash
git clone https://github.com/noah-ing/knowverse.git
cd knowverse
git checkout knowverse-integration  # or main branch
```

### 2. Environment Configuration

Copy the environment template:
```bash
cp .env.example .env
```

Edit `.env` with your configuration:
```bash
# Database
POSTGRES_PASSWORD=secure_password_here

# Redis (optional customization)
REDIS_URL=redis://redis:6379/0

# Haystack AI Service
HAYSTACK_SERVICE_URL=http://haystack:8000

# Rails
SECRET_KEY_BASE=your_secret_key_here
```

### 3. Build and Start Services

```bash
# Build all services
docker-compose build

# Start the complete stack
docker-compose up
```

### 4. Initialize Database

In a new terminal:
```bash
# Run database setup
docker-compose exec rails bundle exec rails db:create db:migrate

# Optional: Load seed data
docker-compose exec rails bundle exec rails db:seed
```

### 5. Access Application

- **Rails Application**: http://localhost:3000
- **Haystack AI Service**: http://localhost:8000
- **PostgreSQL**: localhost:5432
- **Redis**: localhost:6379

## Development Workflow

### Starting Development

```bash
# Start all services
docker-compose up

# Or start in background
docker-compose up -d

# View logs
docker-compose logs -f rails
docker-compose logs -f haystack
```

### Code Changes

- **Rails Code**: Auto-reloads on file changes
- **Python/Haystack**: Auto-reloads with uvicorn --reload
- **Assets**: Run CSS watcher for Tailwind updates

### CSS Development

```bash
# Start Tailwind watcher
docker-compose --profile tools up css
```

### Database Operations

```bash
# Run migrations
docker-compose exec rails bundle exec rails db:migrate

# Rails console
docker-compose exec rails bundle exec rails console

# Database console
docker-compose exec postgres psql -U postgres -d knowverse_development
```

### Background Jobs

Background jobs run automatically via SolidQueue:
```bash
# View worker logs
docker-compose logs -f worker

# Check job queue status
docker-compose exec rails bundle exec rails solid_queue:status
```

### Service Management

```bash
# Restart specific service
docker-compose restart rails
docker-compose restart haystack

# Rebuild after Gemfile changes
docker-compose build rails
docker-compose up -d

# Stop all services
docker-compose down

# Stop and remove volumes (fresh start)
docker-compose down -v
```

## Service Details

### Rails Application

- **Base Image**: ruby:3.3-bullseye
- **Port**: 3000
- **Features**: Full SolidQueue, Redis caching, pgvector support
- **Development**: Hot reload, debugging support

### PostgreSQL with pgvector

- **Image**: pgvector/pgvector:pg14
- **Port**: 5432
- **Extensions**: pgvector auto-enabled
- **Data**: Persistent via Docker volumes

### Redis Cache

- **Image**: redis:7-alpine
- **Port**: 6379
- **Configuration**: Development-optimized with persistence
- **Memory**: 512MB limit with LRU eviction

### Python Haystack Service

- **Base Image**: python:3.11-slim
- **Port**: 8000
- **Features**: FastAPI, embedding generation, RAG endpoints
- **Development**: Hot reload with uvicorn

## Advanced Configuration

### Environment Variables

Key environment variables for customization:

```bash
# Performance
WEB_CONCURRENCY=1
RAILS_MAX_THREADS=3

# SolidQueue
SOLID_QUEUE_IN_PUMA=true

# Haystack Service
HAYSTACK_DEBUG=true
HAYSTACK_MODEL_CACHE=/app/models

# Development
RAILS_ENV=development
DEBUG=true
```

### Volume Mapping

Persistent data volumes:
- `postgres_data`: Database files
- `redis_data`: Redis persistence
- `bundle_cache`: Gem cache for faster builds
- `haystack_models`: AI model cache

### Health Checks

All services include health checks:
- PostgreSQL: `pg_isready` 
- Redis: `redis-cli ping`
- Haystack: HTTP health endpoint
- Rails: Process-based monitoring

### Service Dependencies

Dependency chain ensures proper startup order:
1. PostgreSQL and Redis start first
2. Haystack service waits for database
3. Rails waits for all dependencies
4. Workers start after Rails

## Troubleshooting

### Common Issues

**Port Conflicts**
```bash
# Check for conflicts
netstat -tulpn | grep :3000

# Use different ports
docker-compose -f docker-compose.yml -f docker-compose.override.yml up
```

**Database Connection Issues**
```bash
# Check PostgreSQL logs
docker-compose logs postgres

# Test connection
docker-compose exec postgres pg_isready -U postgres
```

**Build Failures**
```bash
# Clean rebuild
docker-compose down
docker-compose build --no-cache
docker-compose up
```

**Permission Issues (Linux)**
```bash
# Fix ownership
sudo chown -R $(id -u):$(id -g) .
```

### Performance Optimization

**Memory Usage**
```bash
# Monitor container memory
docker stats

# Adjust limits in docker-compose.yml if needed
```

**Build Speed**
```bash
# Use BuildKit for faster builds
export DOCKER_BUILDKIT=1
docker-compose build
```

## Production Deployment

This development setup provides production parity. For deployment:

1. **Environment**: Use production environment variables
2. **Images**: Build optimized production images
3. **Scaling**: Scale worker containers as needed
4. **Security**: Use secrets management for sensitive data
5. **Monitoring**: Add APM and logging solutions

## Migration from Windows Setup

If migrating from Windows-specific setup:

1. **Remove**: All `bin/windows_*` scripts
2. **Clean**: Platform detection code removed
3. **Restore**: Full Redis and background job support
4. **Benefits**: Identical development/production environments

## Support

For issues with this Docker setup:

1. Check service logs: `docker-compose logs [service_name]`
2. Verify health checks: `docker-compose ps`
3. Review environment variables
4. Consult troubleshooting section above

This enterprise Docker environment provides a robust, scalable development experience that matches production deployment exactly.
