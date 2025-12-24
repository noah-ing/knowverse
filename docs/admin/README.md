# KnowVerse Administrator Guide

This guide covers installation, configuration, and administration of KnowVerse.

## Table of Contents

1. [Installation](#installation)
2. [Environment Configuration](#environment-configuration)
3. [SSO Setup (SAML/OIDC)](#sso-setup)
4. [Haystack Service](#haystack-service)
5. [Background Jobs](#background-jobs)
6. [Troubleshooting](#troubleshooting)

---

## Installation

### Requirements

- Ruby 3.2+
- PostgreSQL 14+ with pgvector extension
- Redis 7+
- Python 3.10+ (for Haystack service)
- Node.js 18+ (for asset compilation)

### Docker Deployment (Recommended)

```bash
# Clone the repository
git clone https://github.com/your-org/knowverse.git
cd knowverse

# Copy environment file
cp .env.example .env

# Edit environment variables
vim .env

# Start services
docker-compose up -d
```

### Kamal Deployment

```bash
# Configure Kamal
kamal init

# Edit deploy.yml with your server details

# Deploy
kamal deploy
```

### Manual Installation

```bash
# Install Ruby dependencies
bundle install

# Install JavaScript dependencies
yarn install

# Setup database
bin/rails db:create db:migrate db:seed

# Build assets
bin/rails assets:precompile
bin/rails tailwindcss:build

# Start server
bin/rails server
```

---

## Environment Configuration

### Required Variables

```bash
# Rails
RAILS_ENV=production
SECRET_KEY_BASE=your-secret-key-here
RAILS_MASTER_KEY=your-master-key

# Database
DATABASE_URL=postgres://user:pass@localhost:5432/knowverse_production

# Redis
REDIS_URL=redis://localhost:6379/0

# Email (for magic links)
RESEND_API_KEY=your-resend-key
```

### Haystack Service

```bash
# Haystack API
HAYSTACK_URL=http://localhost:8000
HAYSTACK_API_KEY=your-haystack-key

# OpenAI (for embeddings)
OPENAI_API_KEY=your-openai-key

# Or Anthropic (for RAG)
ANTHROPIC_API_KEY=your-anthropic-key
```

### Connectors

```bash
# Google Drive
GOOGLE_CLIENT_ID=your-client-id
GOOGLE_CLIENT_SECRET=your-client-secret

# Notion
NOTION_CLIENT_ID=your-client-id
NOTION_CLIENT_SECRET=your-client-secret
```

### Security

```bash
# Encryption key for SSO credentials
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=your-32-byte-key
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=your-32-byte-key
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=your-salt
```

---

## SSO Setup

### SAML 2.0 Configuration

#### Organization Admin Steps

1. Navigate to **Organization Settings** > **SSO**
2. Click **Configure SSO**
3. Select **SAML 2.0**
4. Enter your IdP settings:

| Field | Description | Example |
|-------|-------------|---------|
| IdP SSO URL | Login endpoint | `https://idp.okta.com/sso/saml` |
| IdP Certificate | X.509 cert from IdP | `-----BEGIN CERTIFICATE-----...` |
| Name ID Format | Email format (default) | `urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress` |

5. Copy the **SP Metadata** to configure your IdP:
   - Entity ID: `https://knowverse.app/auth/saml/your-org`
   - ACS URL: `https://knowverse.app/auth/saml/your-org/callback`

6. Click **Enable SSO**

#### IdP Configuration (Okta Example)

1. In Okta Admin, go to **Applications** > **Create App**
2. Select **SAML 2.0**
3. Configure:
   - Single Sign On URL: `https://knowverse.app/auth/saml/your-org/callback`
   - Audience URI: `https://knowverse.app/auth/saml/your-org`
   - Name ID format: Email
4. Assign users/groups
5. Copy the IdP metadata to KnowVerse

### OpenID Connect Configuration

#### Organization Admin Steps

1. Navigate to **Organization Settings** > **SSO**
2. Click **Configure SSO**
3. Select **OpenID Connect**
4. Enter your IdP settings:

| Field | Description | Example |
|-------|-------------|---------|
| Issuer | OIDC issuer URL | `https://accounts.google.com` |
| Client ID | OAuth client ID | `123456.apps.googleusercontent.com` |
| Client Secret | OAuth client secret | `GOCSPX-...` |
| Discovery URL | (Optional) | `https://accounts.google.com/.well-known/openid-configuration` |

5. Add the Redirect URI to your IdP:
   - `https://knowverse.app/auth/openid_connect/your-org/callback`

6. Click **Enable SSO**

#### Google Workspace Example

1. Go to Google Cloud Console > **APIs & Services** > **Credentials**
2. Create OAuth 2.0 Client ID
3. Add authorized redirect URI:
   - `https://knowverse.app/auth/openid_connect/your-org/callback`
4. Copy Client ID and Secret to KnowVerse

### SSO Options

| Option | Description | Default |
|--------|-------------|---------|
| Auto-provision | Create users on first login | Enabled |
| Default Role | Role for new SSO users | Viewer |
| Domain Allowlist | Restrict by email domain | Empty (all allowed) |

---

## Haystack Service

The Haystack service handles document processing and AI operations.

### Starting Haystack

```bash
cd services/haystack
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

### Docker

```bash
docker-compose up haystack
```

### Configuration

Edit `services/haystack/.env`:

```bash
# Embedding model
EMBEDDING_MODEL=text-embedding-3-small
EMBEDDING_DIMENSIONS=1536

# LLM for RAG
LLM_PROVIDER=anthropic
LLM_MODEL=claude-sonnet-4-20250514

# Vector store
QDRANT_URL=http://localhost:6333
QDRANT_COLLECTION=knowverse_vectors
```

### Health Check

```bash
curl http://localhost:8000/health
# {"status": "healthy", "version": "2.7.0"}
```

---

## Background Jobs

KnowVerse uses SolidQueue for background processing.

### Job Types

| Job | Description |
|-----|-------------|
| `EmbeddingGenerationWorker` | Generate embeddings for documents |
| `GoogleDriveSyncWorker` | Sync Google Drive files |
| `NotionSyncWorker` | Sync Notion pages |

### Monitoring

View job status in Rails console:

```ruby
SolidQueue::Job.where(finished_at: nil).count
SolidQueue::FailedExecution.count
```

### Retrying Failed Jobs

```ruby
SolidQueue::FailedExecution.all.each(&:retry)
```

---

## Troubleshooting

### Common Issues

#### SSO Login Fails

1. Check SSO configuration is complete:
   ```ruby
   org = Organization.find_by(slug: 'your-org')
   org.sso_config.status
   # => :ready (should be ready, not :incomplete or :disabled)
   ```

2. Verify domain allowlist:
   ```ruby
   org.sso_config.domain_allowed?('user@example.com')
   ```

3. Check Rails logs for OmniAuth errors

#### Documents Not Processing

1. Check Haystack service is running:
   ```bash
   curl http://localhost:8000/health
   ```

2. Check background jobs:
   ```ruby
   SolidQueue::Job.where(class_name: 'DocumentProcessing::EmbeddingGenerationWorker')
                  .where(finished_at: nil)
   ```

3. Check for failed jobs:
   ```ruby
   SolidQueue::FailedExecution.last.error
   ```

#### Search Returns No Results

1. Verify embeddings exist:
   ```ruby
   doc = Document.find(id)
   doc.vector_embeddings.count
   ```

2. Check Qdrant collection:
   ```bash
   curl http://localhost:6333/collections/knowverse_vectors
   ```

3. Test Haystack search directly:
   ```bash
   curl -X POST http://localhost:8000/search \
     -H "Content-Type: application/json" \
     -d '{"query": "test", "organization_id": 1}'
   ```

### Logs

```bash
# Rails application logs
tail -f log/production.log

# Haystack service logs
tail -f services/haystack/logs/app.log

# Background job logs
tail -f log/solid_queue.log
```

### Database Maintenance

```bash
# Vacuum and analyze
bin/rails db:vacuum

# Rebuild vector indexes
bin/rails db:rebuild_vector_indexes
```

---

## Security Considerations

### Encryption

All sensitive data is encrypted:
- SSO credentials (encrypted at rest)
- API keys (encrypted at rest)
- Connector tokens (encrypted at rest)

### Access Control

- Users can only access their organization's data
- Role-based permissions (Owner, Admin, Editor, Viewer)
- API keys scoped to organizations

### Audit Logging

User actions are logged via Ahoy:
```ruby
Ahoy::Event.where(user_id: user.id).last(10)
```

---

*For user documentation, see [User Guide](../user/README.md).*
*For API documentation, see [API Reference](../api/README.md).*
