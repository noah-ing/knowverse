# frozen_string_literal: true

# SearchRouter - Simplified search routing
#
# This is a backwards-compatible wrapper around UnifiedSearchService.
# The old 9-provider implementation has been replaced with Qdrant-based search.
#
# Migration:
#   Old: SearchRouter.route_query(query, org_id, provider: :pgvector_cosine)
#   New: Search::UnifiedSearchService.new.search(query, org_id, mode: :semantic)
#
# The old provider names are mapped to new modes:
#   :pgvector_cosine, :pgvector_l2, :hnsw, :haystack, :distributed → :semantic
#   :hybrid, :hybrid_advanced → :hybrid
#   :domain_aware, :confidence_aware → :semantic (with filtering)
#
class SearchRouter
  # Legacy provider names (for backwards compatibility)
  PROVIDERS = {
    pgvector_cosine: 'Semantic Search',
    pgvector_l2: 'Semantic Search',
    hnsw: 'Semantic Search',
    haystack: 'Semantic Search',
    hybrid: 'Hybrid Search',
    hybrid_advanced: 'Hybrid Search',
    distributed: 'Semantic Search',
    domain_aware: 'Semantic Search',
    confidence_aware: 'Semantic Search'
  }.freeze

  # New simplified modes
  MODES = {
    semantic: 'Vector similarity search via Qdrant',
    keyword: 'PostgreSQL full-text search',
    hybrid: 'Combined semantic + keyword'
  }.freeze

  # Embedding model dimensions (used by HaystackClient)
  MODELS = {
    'base' => 768,
    'small' => 384,
    'large' => 1024,
    'all-MiniLM-L6-v2' => 384,
    'all-mpnet-base-v2' => 768,
    'text-embedding-3-small' => 1536,
    'text-embedding-3-large' => 3072,
    'text-embedding-ada-002' => 1536
  }.freeze

  class << self
    # Main entry point - backwards compatible
    # Returns { results: [...], metadata: {...} } format expected by SearchController
    def route_query(query_text, organization_id, options = {})
      provider = options[:provider]&.to_sym
      mode = map_provider_to_mode(provider)
      model_name = options[:model_name] || 'base'
      rerank = options[:rerank] || false

      start_time = Time.current

      results = service.search(
        query_text,
        organization_id,
        mode: mode,
        rerank: rerank,
        limit: options[:limit] || 10,
        filter: options[:filter],
        score_threshold: options[:min_similarity],
        vector_weight: options[:vector_weight] || 0.7,
        keyword_weight: options[:keyword_weight] || 0.3
      )

      duration_ms = ((Time.current - start_time) * 1000).to_i

      # Return format expected by SearchController
      {
        results: results,
        metadata: {
          provider: mode.to_s,
          model: model_name,
          dimension: MODELS[model_name] || 768,
          duration_ms: duration_ms,
          result_count: results.size
        }
      }
    rescue Search::UnifiedSearchService::CollectionNotFoundError => e
      Rails.logger.warn("Collection not found: #{e.message}. Falling back to empty results.")
      { results: [], metadata: { provider: 'none', error: e.message } }
    rescue Search::UnifiedSearchService::SearchError => e
      Rails.logger.error("Search error: #{e.message}")
      { results: [], metadata: { provider: 'error', error: e.message } }
    end

    # Semantic search (Qdrant)
    def semantic_search(query, organization_id, **options)
      service.search(query, organization_id, mode: :semantic, **options)
    end

    # Keyword search (PostgreSQL)
    def keyword_search(query, organization_id, **options)
      service.search(query, organization_id, mode: :keyword, **options)
    end

    # Hybrid search (Qdrant + PostgreSQL)
    def hybrid_search(query, organization_id, **options)
      service.search(query, organization_id, mode: :hybrid, **options)
    end

    # Batch search
    def batch_search(queries, organization_id, **options)
      service.batch_search(queries, organization_id, **options)
    end

    # Index a document
    def index_document(document)
      service.index_document(document)
    end

    # Bulk index documents
    def bulk_index(documents)
      service.bulk_index(documents)
    end

    # Remove document from index
    def remove_document(document)
      service.remove_document(document)
    end

    # Get search statistics for an organization
    def stats(organization_id)
      service.stats(organization_id)
    end

    # Health check
    def healthy?
      service.healthy?
    end

    # Available providers (for backwards compatibility with admin UI)
    def available_providers
      PROVIDERS.keys
    end

    # Available modes (new API)
    def available_modes
      MODES.keys
    end

    private

    def service
      @service ||= Search::UnifiedSearchService.new
    end

    def map_provider_to_mode(provider)
      case provider
      when :hybrid, :hybrid_advanced
        :hybrid
      when :keyword
        :keyword
      else
        :semantic  # Default to semantic (Qdrant) for all vector-based providers
      end
    end
  end
end
