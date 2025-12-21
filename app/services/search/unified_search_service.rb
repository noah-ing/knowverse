# frozen_string_literal: true

module Search
  # UnifiedSearchService - Clean, fast, production-grade search
  #
  # This replaces the 974-line SearchRouter with 9 providers.
  # Uses Qdrant (Rust) for all vector operations.
  #
  # Architecture:
  #   Rails API → UnifiedSearchService → Qdrant Cluster (Rust)
  #                                    → Haystack (Python) for embeddings
  #
  # Performance:
  #   - Qdrant: Sub-10ms HNSW search (Rust + SIMD)
  #   - Built-in Raft consensus (no Ruby implementation needed)
  #   - 3-way replication, automatic failover
  #
  class UnifiedSearchService
    class SearchError < StandardError; end
    class CollectionNotFoundError < SearchError; end
    class EmbeddingError < SearchError; end

    # Collection naming convention: org_{organization_id}_documents
    COLLECTION_PREFIX = 'knowverse_org_'
    COLLECTION_SUFFIX = '_embeddings'

    # Default search parameters
    DEFAULT_LIMIT = 10
    # Score threshold for cosine similarity (0-1 scale)
    # Low threshold to capture semantic matches - cross-encoder reranking handles precision
    DEFAULT_SCORE_THRESHOLD = 0.1

    def initialize(qdrant: nil, haystack: nil)
      @qdrant = qdrant || default_qdrant_client
      @haystack = haystack || HaystackClient.new
      @cache = Rails.cache
    end

    # Main search entry point
    # Supports: :semantic, :keyword, :hybrid
    # @param rerank [Boolean] Whether to apply cross-encoder reranking (improves relevance)
    def search(query, organization_id, mode: :semantic, rerank: false, **options)
      # Extract hybrid-specific options
      vector_weight = options.delete(:vector_weight) || 0.7
      keyword_weight = options.delete(:keyword_weight) || 0.3

      results = case mode
      when :semantic
        semantic_search(query, organization_id, **options)
      when :keyword
        keyword_search(query, organization_id, **options)
      when :hybrid
        hybrid_search(query, organization_id, vector_weight: vector_weight, keyword_weight: keyword_weight, **options)
      else
        raise ArgumentError, "Unknown search mode: #{mode}. Use :semantic, :keyword, or :hybrid"
      end

      # Apply cross-encoder reranking if requested
      if rerank && results.any?
        results = rerank_results(query, results, options[:limit] || DEFAULT_LIMIT)
      end

      results
    end

    # Pure vector similarity search using Qdrant
    def semantic_search(query, organization_id, limit: DEFAULT_LIMIT, filter: nil, score_threshold: nil)
      collection = collection_name(organization_id)

      # Get embedding from Haystack (cached)
      embedding = get_embedding(query, organization_id)

      # Build organization filter
      qdrant_filter = build_filter(organization_id, filter)

      # Search Qdrant
      result = @qdrant.search(
        collection: collection,
        vector: embedding,
        limit: limit,
        filter: qdrant_filter,
        score_threshold: score_threshold || DEFAULT_SCORE_THRESHOLD,
        with_payload: true
      )

      unless result[:success]
        if result[:error]&.include?('not found')
          raise CollectionNotFoundError, "Collection #{collection} not found. Run migration first."
        end
        raise SearchError, "Qdrant search failed: #{result[:error]}"
      end

      format_results(result[:results], result[:latency_ms])
    end

    # PostgreSQL full-text search (for keyword matching)
    def keyword_search(query, organization_id, limit: DEFAULT_LIMIT, filter: nil)
      documents = Document
        .where(organization_id: organization_id)
        .where(status: 'active')

      # Apply additional filters
      documents = apply_document_filters(documents, filter)

      # PostgreSQL full-text search
      documents = documents
        .where("to_tsvector('english', content) @@ plainto_tsquery('english', ?)", query)
        .order(Arel.sql("ts_rank(to_tsvector('english', content), plainto_tsquery('english', '#{Document.sanitize_sql_like(query)}')) DESC"))
        .limit(limit)

      format_document_results(documents)
    end

    # Hybrid search: combine semantic + keyword with score fusion
    def hybrid_search(query, organization_id, limit: DEFAULT_LIMIT, vector_weight: 0.7, keyword_weight: 0.3, **options)
      # Run both searches in parallel
      semantic_future = Concurrent::Future.execute { semantic_search(query, organization_id, limit: limit * 2, **options) }
      keyword_future = Concurrent::Future.execute { keyword_search(query, organization_id, limit: limit * 2, **options) }

      semantic_results = semantic_future.value(timeout: 10) || []
      keyword_results = keyword_future.value(timeout: 10) || []

      # Score fusion using Reciprocal Rank Fusion (RRF)
      fused = reciprocal_rank_fusion(
        [semantic_results, keyword_results],
        weights: [vector_weight, keyword_weight]
      )

      # Return top results
      fused.first(limit)
    end

    # Batch search for multiple queries
    def batch_search(queries, organization_id, **options)
      collection = collection_name(organization_id)

      # Get embeddings for all queries
      embeddings = queries.map { |q| get_embedding(q, organization_id) }

      # Batch search in Qdrant
      searches = embeddings.map do |embedding|
        {
          vector: embedding,
          limit: options[:limit] || DEFAULT_LIMIT,
          filter: build_filter(organization_id, options[:filter])
        }
      end

      result = @qdrant.search_batch(collection: collection, searches: searches)

      unless result[:success]
        raise SearchError, "Batch search failed: #{result[:error]}"
      end

      result[:results].map.with_index do |results, i|
        {
          query: queries[i],
          results: format_results(results, nil)
        }
      end
    end

    # Upsert a document's embedding to Qdrant
    def index_document(document)
      return unless document.content.present?

      collection = collection_name(document.organization_id)
      ensure_collection_exists(collection)

      # Generate embedding
      embedding = @haystack.generate_embeddings(document.content)

      unless embedding&.is_a?(Array) && embedding.length > 0
        raise EmbeddingError, "Failed to generate embedding for document #{document.id}"
      end

      # Upsert to Qdrant
      result = @qdrant.upsert(
        collection: collection,
        points: [{
          id: document.id,
          vector: embedding,
          payload: document_payload(document)
        }]
      )

      unless result[:success]
        raise SearchError, "Failed to index document #{document.id}: #{result[:error]}"
      end

      result
    end

    # Bulk index documents
    def bulk_index(documents)
      return if documents.empty?

      # Group by organization
      by_org = documents.group_by(&:organization_id)

      results = by_org.map do |org_id, org_docs|
        collection = collection_name(org_id)
        ensure_collection_exists(collection)

        # Generate embeddings in batch
        contents = org_docs.map(&:content)
        embeddings = @haystack.generate_embeddings_batch(contents)

        # Build points
        points = org_docs.zip(embeddings).map do |doc, embedding|
          {
            id: doc.id,
            vector: embedding,
            payload: document_payload(doc)
          }
        end

        @qdrant.upsert(collection: collection, points: points)
      end

      { success: results.all? { |r| r[:success] }, results: results }
    end

    # Bulk index pre-built points (for chunk-level indexing)
    def bulk_index_points(organization_id, points)
      return { success: true, indexed: 0 } if points.empty?

      collection = collection_name(organization_id)
      ensure_collection_exists(collection)

      # Convert string IDs to format Qdrant expects
      formatted_points = points.map do |point|
        {
          id: point[:id].to_s,
          vector: point[:vector],
          payload: point[:payload]
        }
      end

      result = @qdrant.upsert(collection: collection, points: formatted_points)

      if result[:success]
        { success: true, indexed: points.size }
      else
        { success: false, error: result[:error], indexed: 0 }
      end
    end

    # Delete document from index
    def remove_document(document)
      collection = collection_name(document.organization_id)

      @qdrant.delete(collection: collection, ids: [document.id])
    end

    # Get search statistics
    def stats(organization_id)
      collection = collection_name(organization_id)
      info = @qdrant.collection_info(collection)

      return { exists: false } unless info[:status] == 'green'

      {
        exists: true,
        vectors_count: info[:vectors_count],
        points_count: info[:points_count],
        segments_count: info[:segments_count],
        status: info[:status]
      }
    end

    # Health check - works with both cluster mode and single-node mode
    def healthy?
      status = @qdrant.cluster_status
      # Accept both cluster mode ('enabled') and single-node mode ('disabled')
      # 'disabled' means clustering is disabled, not that Qdrant is down
      %w[enabled disabled].include?(status[:status])
    rescue StandardError
      false
    end

    private

    def default_qdrant_client
      urls = ENV.fetch('QDRANT_CLUSTER_URLS', 'http://localhost:6333').split(',')
      api_key = ENV['QDRANT_API_KEY']

      VectorStore::QdrantClusterAdapter.new(
        cluster_urls: urls,
        api_key: api_key
      )
    end

    def collection_name(organization_id)
      "#{COLLECTION_PREFIX}#{organization_id}#{COLLECTION_SUFFIX}"
    end

    def ensure_collection_exists(collection)
      # Check cache first
      return if @cache.exist?("collection_exists:#{collection}")

      info = @qdrant.collection_info(collection)

      if info[:status] == 'error' && info[:error]&.downcase&.include?('not found')
        # Create collection with optimal settings
        result = @qdrant.create_collection(
          name: collection,
          dimension: embedding_dimension,
          distance: :cosine,
          replication_factor: 3
        )

        unless result[:success]
          raise SearchError, "Failed to create collection: #{result[:error]}"
        end
      end

      # Cache for 1 hour
      @cache.write("collection_exists:#{collection}", true, expires_in: 1.hour)
    end

    def embedding_dimension
      # Default to 768 for all-mpnet-base-v2
      ENV.fetch('EMBEDDING_DIMENSION', 768).to_i
    end

    def get_embedding(query, organization_id)
      cache_key = "embedding:#{Digest::SHA256.hexdigest(query)}:#{organization_id}"

      @cache.fetch(cache_key, expires_in: 1.hour) do
        # Use generate_embeddings with options hash (supports monkey-patched caching)
        embedding = @haystack.generate_embeddings(query, organization_id: organization_id)

        unless embedding&.is_a?(Array) && embedding.size > 0
          raise EmbeddingError, "Failed to generate embedding for query"
        end

        embedding
      end
    end

    def build_filter(organization_id, additional_filter = nil)
      # Only filter by organization_id - chunks don't have document-level status
      must_conditions = [
        { key: 'organization_id', match: { value: organization_id } }
      ]

      if additional_filter
        additional_filter.each do |key, value|
          must_conditions << { key: key.to_s, match: { value: value } }
        end
      end

      { must: must_conditions }
    end

    def document_payload(document)
      {
        organization_id: document.organization_id,
        title: document.title,
        file_name: document.file_path,
        file_type: document.file_type,
        status: document.status || 'active',
        created_at: document.created_at&.iso8601,
        updated_at: document.updated_at&.iso8601,
        # Include snippet for display
        snippet: document.content&.truncate(500)
      }
    end

    def apply_document_filters(scope, filter)
      return scope unless filter

      filter.each do |key, value|
        case key.to_sym
        when :content_type
          scope = scope.where(content_type: value)
        when :created_after
          scope = scope.where('created_at > ?', value)
        when :created_before
          scope = scope.where('created_at < ?', value)
        end
      end

      scope
    end

    def format_results(qdrant_results, latency_ms)
      results = qdrant_results.map.with_index do |result, rank|
        payload = result[:payload] || {}
        # Document ID is stored in payload (integer), point ID is the chunk UUID
        doc_id = payload['document_id'] || payload[:document_id] || result[:id]
        {
          'document_id' => doc_id,
          'chunk_id' => result[:id],
          'score' => result[:score],
          'distance' => result[:distance],
          'rank' => rank + 1,
          'title' => payload['title'] || payload[:title],
          'snippet' => payload['content'] || payload[:content] || payload['snippet']&.to_s&.truncate(300),
          'file_name' => payload['file_name'] || payload[:file_name],
          'file_type' => payload['file_type'] || payload[:file_type],
          'chunk_index' => payload['chunk_index'] || payload[:chunk_index],
          'source' => 'qdrant'
        }
      end

      # Deduplicate by document - keep only the highest-scoring chunk per document
      deduplicate_by_document(results)
    end

    # Keep only the best-scoring chunk per document
    def deduplicate_by_document(results)
      best_by_doc = {}

      results.each do |result|
        doc_id = result['document_id']
        existing = best_by_doc[doc_id]

        # Keep the result with the highest score for each document
        if existing.nil? || (result['score'] || 0) > (existing['score'] || 0)
          best_by_doc[doc_id] = result
        end
      end

      # Return deduplicated results, re-ranked by score
      best_by_doc.values.sort_by { |r| -(r['score'] || 0) }.each_with_index.map do |result, idx|
        result['rank'] = idx + 1
        result
      end
    end

    def format_document_results(documents)
      documents.map.with_index do |doc, rank|
        {
          'document_id' => doc.id,
          'score' => 1.0, # Keyword search doesn't have similarity score
          'rank' => rank + 1,
          'title' => doc.title,
          'file_name' => doc.file_name,
          'snippet' => doc.content&.truncate(500),
          'source' => 'keyword'
        }
      end
    end

    # Rerank results using cross-encoder model via Haystack service
    # Cross-encoder provides more accurate relevance scores than bi-encoder
    def rerank_results(query, results, limit)
      return results if results.empty?

      begin
        response = @haystack.rerank(
          query: query,
          documents: results,
          top_k: limit
        )

        if response.success? && response.data['results'].present?
          # Merge rerank scores back into results
          reranked = response.data['results'].map.with_index do |r, idx|
            result = r.dup
            result['rank'] = idx + 1
            result['original_score'] = result['score']
            result['score'] = result['rerank_score'] || result['score']
            result
          end
          Rails.logger.info("Reranked #{results.size} results to top #{reranked.size}")
          reranked
        else
          Rails.logger.warn("Reranking failed, returning original results")
          results
        end
      rescue => e
        Rails.logger.error("Reranking error: #{e.message}")
        results # Return original results on error
      end
    end

    # Reciprocal Rank Fusion for combining multiple result sets
    # https://plg.uwaterloo.ca/~gvcormac/cormacksigir09-rrf.pdf
    def reciprocal_rank_fusion(result_sets, weights: nil, k: 60)
      weights ||= Array.new(result_sets.length, 1.0 / result_sets.length)
      scores = Hash.new(0.0)
      docs = {}

      result_sets.each_with_index do |results, set_idx|
        results.each_with_index do |result, rank|
          doc_id = result['document_id']
          # RRF formula: 1 / (k + rank)
          rrf_score = weights[set_idx] * (1.0 / (k + rank + 1))
          scores[doc_id] += rrf_score
          docs[doc_id] ||= result
        end
      end

      # Sort by fused score
      scores.sort_by { |_, score| -score }.map do |doc_id, fused_score|
        docs[doc_id].merge(
          'fused_score' => fused_score,
          'score' => fused_score
        )
      end
    end
  end
end
