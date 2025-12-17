# frozen_string_literal: true

# Rake tasks for migrating from pgvector to Qdrant
#
# Usage:
#   bundle exec rake qdrant:status              # Check Qdrant cluster health
#   bundle exec rake qdrant:migrate             # Migrate all documents to Qdrant
#   bundle exec rake qdrant:migrate[org_123]    # Migrate specific organization
#   bundle exec rake qdrant:verify[org_123]     # Verify migration for organization
#   bundle exec rake qdrant:benchmark           # Run performance benchmark

namespace :qdrant do
  desc "Check Qdrant cluster status"
  task status: :environment do
    search = Search::UnifiedSearchService.new

    if search.healthy?
      puts "✅ Qdrant cluster is healthy"

      qdrant = VectorStore::QdrantClusterAdapter.new(
        cluster_urls: ENV.fetch('QDRANT_CLUSTER_URLS', 'http://localhost:6333').split(',')
      )

      status = qdrant.cluster_status
      puts "\nCluster Info:"
      puts "  Status: #{status[:status]}"
      puts "  Peer ID: #{status[:peer_id]}"
      puts "  Peers: #{status[:peers]&.keys&.join(', ')}"

      if status[:raft_info]
        puts "\nRaft Consensus:"
        puts "  Term: #{status[:raft_info]['term']}"
        puts "  Commit: #{status[:raft_info]['commit']}"
        puts "  Leader: #{status[:raft_info]['is_leader'] ? 'Yes' : 'No'}"
      end
    else
      puts "❌ Qdrant cluster is not healthy"
      puts "   Make sure the cluster is running: docker-compose -f docker-compose.production.yml up -d"
    end
  end

  desc "Migrate documents from pgvector to Qdrant"
  task :migrate, [:organization_id] => :environment do |_t, args|
    search = Search::UnifiedSearchService.new
    haystack = HaystackClient.new

    unless search.healthy?
      puts "❌ Qdrant cluster is not healthy. Aborting migration."
      exit 1
    end

    organizations = if args[:organization_id]
      Organization.where(id: args[:organization_id])
    else
      Organization.all
    end

    total_migrated = 0
    total_failed = 0

    organizations.find_each do |org|
      puts "\n📁 Migrating organization: #{org.name} (ID: #{org.id})"

      documents = Document.where(organization_id: org.id, status: 'active')
      total = documents.count

      puts "   Found #{total} documents to migrate"

      # Process in batches
      documents.find_in_batches(batch_size: 100) do |batch|
        begin
          # Check if we have existing embeddings in pgvector
          docs_with_embeddings = batch.select do |doc|
            doc.vector_embeddings.any?
          end

          docs_needing_embeddings = batch - docs_with_embeddings

          # For docs with existing embeddings, use those
          points_existing = docs_with_embeddings.map do |doc|
            embedding = doc.vector_embeddings.first&.embedding
            next unless embedding

            {
              id: doc.id,
              vector: embedding,
              payload: {
                organization_id: doc.organization_id,
                title: doc.title,
                file_name: doc.file_name,
                content_type: doc.content_type,
                status: 'active',
                snippet: doc.content&.truncate(500)
              }
            }
          end.compact

          # For docs needing embeddings, generate via Haystack
          points_new = []
          docs_needing_embeddings.each do |doc|
            next unless doc.content.present?

            begin
              embedding = haystack.generate_embedding(doc.content)
              if embedding&.is_a?(Array) && embedding.length > 0
                points_new << {
                  id: doc.id,
                  vector: embedding,
                  payload: {
                    organization_id: doc.organization_id,
                    title: doc.title,
                    file_name: doc.file_name,
                    content_type: doc.content_type,
                    status: 'active',
                    snippet: doc.content&.truncate(500)
                  }
                }
              end
            rescue StandardError => e
              puts "   ⚠️  Failed to generate embedding for doc #{doc.id}: #{e.message}"
            end
          end

          all_points = points_existing + points_new

          if all_points.any?
            qdrant = VectorStore::QdrantClusterAdapter.new(
              cluster_urls: ENV.fetch('QDRANT_CLUSTER_URLS', 'http://localhost:6333').split(',')
            )

            collection = "org_#{org.id}_documents"

            # Ensure collection exists
            qdrant.create_collection(
              name: collection,
              dimension: all_points.first[:vector].length,
              distance: :cosine
            )

            result = qdrant.upsert(collection: collection, points: all_points)

            if result[:success]
              total_migrated += all_points.length
              print "."
            else
              total_failed += all_points.length
              puts "\n   ❌ Batch upsert failed: #{result[:error]}"
            end
          end
        rescue StandardError => e
          total_failed += batch.length
          puts "\n   ❌ Batch migration failed: #{e.message}"
        end
      end

      puts "\n   ✅ Completed: #{total_migrated} migrated"
    end

    puts "\n" + "=" * 50
    puts "Migration Complete"
    puts "  Migrated: #{total_migrated}"
    puts "  Failed: #{total_failed}"
    puts "=" * 50
  end

  desc "Verify migration for an organization"
  task :verify, [:organization_id] => :environment do |_t, args|
    unless args[:organization_id]
      puts "Usage: rake qdrant:verify[organization_id]"
      exit 1
    end

    search = Search::UnifiedSearchService.new
    org_id = args[:organization_id].to_i

    # Get stats from Qdrant
    stats = search.stats(org_id)

    unless stats[:exists]
      puts "❌ Collection does not exist for organization #{org_id}"
      exit 1
    end

    # Compare with database
    db_count = Document.where(organization_id: org_id, status: 'active').count

    puts "Verification for Organization #{org_id}:"
    puts "  Documents in DB: #{db_count}"
    puts "  Vectors in Qdrant: #{stats[:vectors_count]}"
    puts "  Points in Qdrant: #{stats[:points_count]}"
    puts "  Collection status: #{stats[:status]}"

    if stats[:vectors_count] == db_count
      puts "\n✅ Migration verified - counts match"
    else
      puts "\n⚠️  Count mismatch - some documents may need re-indexing"
    end
  end

  desc "Benchmark search performance"
  task :benchmark, [:organization_id] => :environment do |_t, args|
    unless args[:organization_id]
      puts "Usage: rake qdrant:benchmark[organization_id]"
      exit 1
    end

    search = Search::UnifiedSearchService.new
    org_id = args[:organization_id].to_i

    queries = [
      "machine learning algorithms",
      "data processing pipeline",
      "user authentication flow",
      "database optimization",
      "API integration patterns"
    ]

    puts "Running benchmark for organization #{org_id}..."
    puts "=" * 50

    # Warmup
    queries.each { |q| search.search(q, org_id) rescue nil }

    # Semantic search benchmark
    semantic_times = []
    queries.each do |query|
      10.times do
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        search.search(query, org_id, mode: :semantic)
        elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
        semantic_times << elapsed
      end
    end

    # Hybrid search benchmark
    hybrid_times = []
    queries.each do |query|
      10.times do
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        search.search(query, org_id, mode: :hybrid)
        elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
        hybrid_times << elapsed
      end
    end

    puts "\nSemantic Search (Qdrant):"
    puts "  Average: #{(semantic_times.sum / semantic_times.length).round(2)}ms"
    puts "  P50: #{semantic_times.sort[semantic_times.length / 2].round(2)}ms"
    puts "  P99: #{semantic_times.sort[(semantic_times.length * 0.99).to_i].round(2)}ms"
    puts "  Min: #{semantic_times.min.round(2)}ms"
    puts "  Max: #{semantic_times.max.round(2)}ms"

    puts "\nHybrid Search (Qdrant + PostgreSQL):"
    puts "  Average: #{(hybrid_times.sum / hybrid_times.length).round(2)}ms"
    puts "  P50: #{hybrid_times.sort[hybrid_times.length / 2].round(2)}ms"
    puts "  P99: #{hybrid_times.sort[(hybrid_times.length * 0.99).to_i].round(2)}ms"

    puts "\n" + "=" * 50
  end

  desc "Create test collection and run sample search"
  task test: :environment do
    puts "Testing Qdrant integration..."

    qdrant = VectorStore::QdrantClusterAdapter.new(
      cluster_urls: ENV.fetch('QDRANT_CLUSTER_URLS', 'http://localhost:6333').split(',')
    )

    collection = "test_collection_#{Time.now.to_i}"

    # Create collection
    puts "\n1. Creating test collection..."
    result = qdrant.create_collection(name: collection, dimension: 768)
    puts "   #{result[:success] ? '✅' : '❌'} Create collection: #{result}"

    # Insert test vectors
    puts "\n2. Inserting test vectors..."
    test_points = 10.times.map do |i|
      {
        id: i + 1,
        vector: Array.new(768) { rand(-1.0..1.0) },
        payload: { test_id: i, name: "Test Document #{i}" }
      }
    end

    result = qdrant.upsert(collection: collection, points: test_points)
    puts "   #{result[:success] ? '✅' : '❌'} Upsert: #{result[:batches]} batches"

    # Search
    puts "\n3. Testing search..."
    query_vector = Array.new(768) { rand(-1.0..1.0) }
    result = qdrant.search(collection: collection, vector: query_vector, limit: 5)
    puts "   #{result[:success] ? '✅' : '❌'} Search latency: #{result[:latency_ms]&.round(2)}ms"
    puts "   Results: #{result[:results]&.length || 0} documents"

    # Cleanup
    puts "\n4. Cleaning up..."
    # Note: Would delete collection here in real test

    puts "\n✅ Qdrant integration test completed!"
  end
end
