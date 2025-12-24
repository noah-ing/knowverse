# Knowverse Changelog

All notable changes to the Knowverse project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.8.0] - 2025-12-24

### Added - SSO/SAML + OIDC (Week 11-12)
- **SAML 2.0 Support**: Enterprise SSO with Okta, Azure AD, OneLogin, PingFederate
- **OpenID Connect Support**: Google Workspace, Auth0, Okta OIDC, Azure AD OIDC
- **Per-Organization SSO Config**: Each org has independent SSO settings with encrypted credentials
- **JIT User Provisioning**: Auto-create users on first SSO login with configurable default role
- **Domain Allowlist**: Restrict SSO to specific email domains per organization
- **SSO Admin UI**: Wizard for SAML/OIDC setup, metadata display, test connection

### Added - Comprehensive Documentation
- **API Documentation**: Full endpoint reference with authentication, examples, rate limits
- **User Guide**: Getting started, uploading, searching, RAG chat, connectors, SSO login
- **Admin Guide**: Installation, environment config, SSO setup, Haystack service, troubleshooting

### Added - Legal & Compliance
- **Privacy Policy**: Comprehensive GDPR/CCPA-compliant privacy policy at `/privacy`
- **Terms of Service**: Full terms and conditions with 20 sections at `/terms`
- **Cookie Policy**: Detailed cookie categories and usage at `/cookies`
- **Cookie Consent Banner**: GDPR-compliant consent with essential/functional/analytics categories
- **Cookie Preferences Modal**: Granular control over cookie types with save preferences

### Technical
- `app/models/sso_config.rb` - SSO configuration with Active Record Encryption
- `app/services/sso/user_provisioner.rb` - JIT user provisioning with domain validation
- `app/controllers/users/omniauth_callbacks_controller.rb` - SAML/OIDC callback handling
- `app/controllers/sso_configs_controller.rb` - Organization SSO management
- `app/controllers/sso_controller.rb` - SSO login flow
- `config/initializers/omniauth.rb` - Dynamic per-org provider configuration
- `app/javascript/controllers/cookie_consent_controller.js` - Cookie consent Stimulus controller
- `app/views/shared/_cookie_consent.html.erb` - Cookie banner and settings modal
- `docs/api/README.md`, `docs/user/README.md`, `docs/admin/README.md` - Documentation

---

## [2.7.0] - 2025-12-24

### Added - Chunk-Level Citations UI (Week 9-10)
- **Post-hoc Citation Attribution**: Sentences automatically attributed to source chunks via semantic similarity
- **Inline Citation Markers**: `[1] [2]` markers inserted at sentence ends linking to sources
- **Citation Popovers**: Hover to see chunk preview, document title, and "View in document" link
- **Source Pills with Chunk Info**: Citation number badges, chunk index display, hover previews
- **Document Chunk Highlighting**: Click citation to navigate to document with chunk highlighted and scrolled into view

### Technical
- `services/haystack/app/citations.py` - CitationEngine with embedding-based attribution
- `app/javascript/controllers/rag_controller.js` - Citation marker injection and popover UI
- `app/javascript/controllers/chunk_highlight_controller.js` - URL hash-based chunk navigation
- `app/views/documents/show.html.erb` - Chunk anchors and highlight controller
- `app/assets/stylesheets/application.tailwind.css` - Citation and highlight animations

---

## [2.6.0] - 2025-12-24

### Added - Agentic RAG (Week 7-8)
- **ReAct Agent**: Reason→Act→Observe loop with tool use for complex queries
- **Deep Research Mode**: Multi-source investigation with query decomposition and synthesis
- **Plan-Execute Agent**: Explicit planning with topological step execution
- **Tool Registry**: 5 built-in tools (search_knowledge_base, calculate, summarize, compare, clarify)
- **Agent Orchestrator**: Auto-detection of query type to select optimal agent mode
- **SSE Streaming**: 18 event types for real-time agent progress (thought, action, observation, plan, etc.)

### Technical
- `services/haystack/app/agents/` - Agent module with base, react, deep_research, plan_execute, orchestrator
- `services/haystack/app/tools.py` - Tool definitions with OpenAI/Anthropic format conversion
- `app/controllers/rag_controller.rb` - `agent_stream` action for agentic RAG
- `app/services/haystack_client.rb` - `generate_agent_stream` method

---

## [2.5.0] - 2025-12-24

### Added - Notion Connector
- **OAuth 2.0 Integration**: Secure Notion workspace connection
- **Page & Database Import**: Sync Notion pages with full content extraction
- **Background Sync**: Sidekiq worker for async document import
- **UI**: Connect button in Documents page, Notion management page

### Technical
- `app/controllers/connectors/notion_controller.rb` - OAuth flow
- `app/services/connectors/notion_service.rb` - Notion API client
- `app/sidekiq/connectors/notion_sync_worker.rb` - Background sync

---

## [2.4.0] - 2025-12-24

### Added - Google Drive Connector (Priority 3)
- **OAuth 2.0 Integration**: Secure Google Drive connection with token refresh
- **Document Sync**: Import PDFs, Google Docs, Sheets, Word files, and more
- **Background Processing**: Sidekiq worker for async file sync
- **Export Support**: Auto-exports Google Docs to PDF, Sheets to XLSX
- **Status Tracking**: Connected/syncing/error states with last sync time
- **UI**: Connect button in Documents page, dedicated Drive management page

### Added - Document Sources Infrastructure
- **DocumentSource Model**: Encrypted credential storage, multi-connector support
- **External Document Tracking**: external_id and external_url on documents
- **Connector Architecture**: Extensible for Notion, Slack, Confluence, GitHub

### Fixed
- **Dark Mode Removal**: Removed dark mode classes from upload UI (white-only design)

### Technical
- `app/models/document_source.rb` - Encrypted credentials, OAuth helpers
- `app/services/connectors/google_drive_service.rb` - Drive API client
- `app/controllers/connectors/google_drive_controller.rb` - OAuth flow
- `app/sidekiq/connectors/google_drive_sync_worker.rb` - Background sync
- `db/migrate/20251224031330_create_document_sources.rb` - Connector tables

---

## [2.3.0] - 2025-12-22

### Added - MCP Server Integration (Phase 1.1)
- **MCP Controller**: Model Context Protocol endpoints for Claude Desktop integration
- **Tools**: `search_documents`, `get_document`, `ask_question`
- **Resources**: List and fetch organization documents via MCP
- **Auth**: API key authentication via `X-MCP-Key` header

### Added - Batch Upload UI (Phase 1.2)
- **Drag & Drop**: Multi-file upload with drag-and-drop support
- **File Management**: Add/remove files before upload, file type icons, size display
- **Async Processing**: Background job processing via SolidQueue (prevents server blocking)
- **Processing Status Bar**: Real-time progress indicator with indigo-purple gradient
- **Bulk Delete**: Select multiple documents with checkboxes, bulk delete with confirmation

### Added - Document Management
- **Select All**: Checkbox to select all visible documents
- **Bulk Actions Bar**: Appears when documents selected, shows count
- **Auto-Refresh**: Status bar auto-refreshes while documents are processing

### Technical
- `app/controllers/mcp_controller.rb` - MCP protocol endpoints
- `app/services/mcp/tool_executor.rb` - Tool execution logic
- `app/javascript/controllers/batch_upload_controller.js` - Drag-drop UI
- `app/javascript/controllers/bulk_select_controller.js` - Multi-select functionality
- `app/javascript/controllers/auto_refresh_controller.js` - Status polling

---

## [2.2.0] - 2025-12-21

### Added - UI/UX Improvements
- **Recent Activity Feed**: Organization dashboard now shows live activity including document uploads, processing completions, searches, RAG conversations, and embedding generations with distinct icons and colors
- **Vector Visualization**: Complete 3D vector space visualization with Three.js, including t-SNE/UMAP projections, interactive controls, and available projections table
- **Clusters Tab**: Document clustering analysis with K-Means, Hierarchical, and DBSCAN algorithms
- **Comparison Tab**: Document similarity comparison and semantic search for finding similar documents

### Fixed - Tab Navigation
- Fixed Document Filters and Time Range tabs on search page (Stimulus controller methods were missing)
- Fixed Clusters and Comparison tabs on vectors page (controller scope didn't include panels)
- Fixed `@hotwire/stimulus` import typo to `@hotwired/stimulus` in document_filters_controller

### Changed - Design System
- **Berkeley Mono Font**: Applied globally across the application for consistent monospace typography
- **RAG Chat UI**: Aligned chat interface styling with homepage preview card design
- **Profile Improvements**: Fixed avatar tracking and display across navigation and profile pages

---

## [2.1.0] - 2025-12-16

### Changed - Honest Documentation Overhaul
- Rewrote README.md to remove marketing claims and provide accurate status
- Created ARCHITECTURE_NEXT_GEN.md with actual architecture details
- Updated all documentation to reflect real capabilities vs aspirational goals

### Added - Phase 5 Production Hardening
- `app/services/vector_store/qdrant_cluster_adapter.rb` - Qdrant cluster integration
- `app/services/wasm/component_sandbox.rb` - WASM orchestration layer (simulation)
- `app/services/infrastructure/rate_limiter.rb` - Token bucket rate limiting
- `app/services/infrastructure/metrics_exporter.rb` - Prometheus metrics

### Added - Phase 4 Scalable Index Architecture
- `app/services/wasm/scalable_index_manager.rb` - Hierarchical partitioning
- Tiered storage: Hot (memory) / Warm (SSD) / Cold (archive)
- LRU eviction with configurable limits

### Added - Phase 3 Real Distributed Consensus
- `app/services/distributed/consensus/raft_node.rb` - Full Raft state machine
- `app/services/distributed/consensus/raft_rpc.rb` - HTTP transport
- `app/services/distributed/consensus/raft_storage.rb` - Persistent WAL
- `app/services/distributed/search/remote_shard_client.rb` - Cross-shard queries
- `app/services/distributed/monitoring/cluster_health_monitor.rb` - Health tracking

### Added - Phase 2 Search Provider Completion
- Fixed `domain_aware` provider - now actually implemented
- Fixed `confidence_aware` provider - multi-strategy parallel execution
- **CRITICAL FIX**: Removed mock embedding fallback that corrupted search results

### Added - Phase 1 Document Processing
- Real PDF extraction via Haystack service (pdfplumber)
- Real DOCX extraction via Haystack service (python-docx)
- Real Excel extraction via Haystack service (fastexcel)
- Semantic, sentence, and fixed-size chunking strategies

---

## [2.0.0] - 2025-05-31

### What Actually Works
- Rails 8 infrastructure with multi-tenant auth
- PostgreSQL + pgvector for similarity search
- Redis two-tier caching
- Sidekiq/SolidQueue background jobs
- Text file processing (TXT, MD, RTF)
- 7 of 9 search providers functional (pgvector_cosine, pgvector_l2, haystack, hybrid, hybrid_advanced, distributed, hnsw)
- SSE streaming for RAG responses

### What Was Claimed But Not Real
- PDF/DOCX extraction returned placeholder strings
- Excel support was not implemented
- HNSW claimed "WebAssembly SIMD acceleration" but was Ruby brute-force
- Raft consensus was 100% logging stubs
- Remote shard queries returned empty arrays
- "Fine-tuned models" did not exist
- "domain_aware" and "confidence_aware" providers fell through to hybrid

### Documentation Notes
This release previously claimed metrics like "89/100 Production Ready" and "2,847 queries/second" that were never validated. The security documentation described SOC2 and HIPAA compliance frameworks that are aspirational, not certified.

---

## [1.5.0] - 2025-04-28

### Added
- SolidQueue integration (replaced Sidekiq)
- Multi-dimensional vector support (384-2048 dimensions)
- Domain confidence scoring framework
- Organization templates

### Changed
- Upgraded to Rails 8.0
- Enhanced vector storage schema

---

## [1.0.0] - 2025-04-01

### Added
- Initial platform with magic link authentication
- User and organization management
- Basic PostgreSQL full-text search
- Document upload (PDF, DOCX, TXT via Active Storage)
- Admin dashboard
- Basic analytics

### Technical Foundation
- Rails 7.0
- PostgreSQL with full-text search
- TailwindCSS
- Hotwire
- RSpec

---

## Current Status (December 2025)

| Component | Status | Notes |
|-----------|--------|-------|
| Rails 8 API | Working | Multi-tenant, auth, background jobs |
| PostgreSQL + pgvector | Working | Cosine & L2 similarity search |
| Redis caching | Working | Two-tier cache |
| Text file processing | Working | TXT, MD, RTF |
| 9 Search Providers | Working | All functional after remediation |
| PDF/DOCX/Excel Extraction | Working | Via Haystack service |
| Raft Consensus | Implemented | Ruby, not battle-tested |
| WASM Components | Simulated | Orchestration only, needs real WASM |
| Qdrant Integration | Adapter Only | Requires external Qdrant cluster |
| Embedding Generation | Conditional | Requires Haystack service |
| Scale Testing | Not Done | 100M+ vectors untested |

### Known Limitations
1. HNSW uses Ruby brute-force, not WASM SIMD
2. Scale architecture designed but untested beyond ~10K vectors
3. Raft implementation not battle-tested for production
4. WASM sandbox needs actual WASM component compilation
5. Security compliance docs are frameworks/aspirations, not certifications

---

*Honest assessment following comprehensive code audit - December 2025*
