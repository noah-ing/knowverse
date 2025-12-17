namespace :embedding_cache do
  desc "Warm the embedding cache with frequent queries for one or all organizations"
  task :warm, [:org_id, :source, :limit] => :environment do |t, args|
    # Parse arguments with defaults
    org_id = args[:org_id].present? ? args[:org_id].to_i : nil
    source = args[:source].present? ? args[:source].to_sym : :popular_queries
    limit = args[:limit].present? ? args[:limit].to_i : 100
    
    puts "Starting cache warming process..."
    
    # Get cache manager
    cache_manager = EmbeddingCache::CacheManager.instance
    
    # Process for a specific organization
    if org_id.present?
      # Verify the organization exists
      organization = Organization.find_by(id: org_id)
      
      if organization
        puts "Warming cache for organization: #{organization.name} (ID: #{org_id})"
        warmed_count = cache_manager.warm_cache(
          org_id, 
          source: source, 
          limit: limit,
          models: ['base']  # Default to base model for now
        )
        puts "Enqueued #{warmed_count} queries for warming from #{source}."
      else
        puts "Error: Organization with ID #{org_id} not found."
      end
    else
      # Process for all organizations
      puts "Warming cache for all organizations..."
      
      # Find all organizations
      Organization.find_each do |org|
        puts "  Organization: #{org.name} (ID: #{org.id})"
        warmed_count = cache_manager.warm_cache(
          org.id,
          source: source,
          limit: limit,
          models: ['base']  # Default to base model for now
        )
        puts "  Enqueued #{warmed_count} queries for warming from #{source}."
      end
    end
    
    puts "Cache warming tasks have been enqueued. Monitor Sidekiq dashboard for progress."
  end
  
  desc "Clear the embedding cache for one or all organizations"
  task :clear, [:org_id, :tier] => :environment do |t, args|
    # Parse arguments with defaults
    org_id = args[:org_id].present? ? args[:org_id].to_i : nil
    tier = args[:tier].present? ? args[:tier].to_sym : :all
    
    # Get cache manager
    cache_manager = EmbeddingCache::CacheManager.instance
    
    if org_id.present?
      # Verify the organization exists
      organization = Organization.find_by(id: org_id)
      
      if organization
        puts "Clearing cache for organization: #{organization.name} (ID: #{org_id})"
        cache_manager.clear_organization(org_id)
        puts "Cache cleared."
      else
        puts "Error: Organization with ID #{org_id} not found."
      end
    else
      # Ask for confirmation before clearing all caches
      print "Are you sure you want to clear cache for ALL organizations? This cannot be undone. [y/N]: "
      response = STDIN.gets.chomp.downcase
      
      if response == 'y'
        puts "Clearing cache for all organizations..."
        Organization.find_each do |org|
          puts "  Clearing for organization: #{org.name} (ID: #{org.id})"
          cache_manager.clear_organization(org.id)
        end
        puts "All caches cleared."
      else
        puts "Operation cancelled."
      end
    end
  end
  
  desc "Show cache statistics (overall or for a specific organization)"
  task :stats, [:org_id] => :environment do |t, args|
    # Parse arguments with defaults
    org_id = args[:org_id].present? ? args[:org_id].to_i : nil
    
    # Get cache manager
    cache_manager = EmbeddingCache::CacheManager.instance
    
    if org_id.present?
      # Verify the organization exists
      organization = Organization.find_by(id: org_id)
      
      if organization
        puts "Cache statistics for organization: #{organization.name} (ID: #{org_id})"
        stats = cache_manager.organization_stats(org_id)
        
        # Display memory tier stats
        puts "\nMemory Tier:"
        puts "  Entries: #{stats[:memory][:size]}"
        puts "  Memory used: #{(stats[:memory][:memory_bytes].to_f / 1_048_576).round(2)} MB"
        
        # Display Redis tier stats
        puts "\nRedis Tier:"
        puts "  Entries: #{stats[:redis][:size]}"
        
        # Display domain stats if available
        if stats[:redis][:domains].present?
          puts "\nDomain-specific counts (Redis tier):"
          stats[:redis][:domains].each do |domain|
            puts "  #{domain[:domain]}: #{domain[:count]} entries"
          end
        end
        
        # Display analytics
        puts "\nCache Analytics:"
        puts "  Hit rate: #{(stats[:analytics][:hit_rate] * 100).round(2)}%"
        puts "  Memory tier hit rate: #{(stats[:analytics][:memory_hit_rate] * 100).round(2)}%"
        puts "  Redis tier hit rate: #{(stats[:analytics][:redis_hit_rate] * 100).round(2)}%"
        puts "  Total requests: #{stats[:analytics][:total_requests]}"
      else
        puts "Error: Organization with ID #{org_id} not found."
      end
    else
      # Display overall stats
      puts "Overall cache statistics:"
      stats = cache_manager.stats
      
      # Display memory tier stats
      puts "\nMemory Tier:"
      puts "  Entries: #{stats[:memory][:size]}"
      puts "  Memory used: #{(stats[:memory][:memory_bytes].to_f / 1_048_576).round(2)} MB"
      puts "  Maximum entries: #{EmbeddingCache::MemoryStore::DEFAULT_MAX_ENTRIES}"
      puts "  Maximum memory: #{(EmbeddingCache::MemoryStore::DEFAULT_MAX_MEMORY.to_f / 1_048_576).round(2)} MB"
      
      # Display Redis tier stats
      puts "\nRedis Tier:"
      puts "  Entries: #{stats[:redis][:size]}"
      
      # Display analytics
      puts "\nCache Analytics:"
      puts "  Overall hit rate: #{(stats[:analytics][:hit_rate] * 100).round(2)}%"
      puts "  Memory tier hit rate: #{(stats[:analytics][:memory_hit_rate] * 100).round(2)}%"
      puts "  Redis tier hit rate: #{(stats[:analytics][:redis_hit_rate] * 100).round(2)}%"
      puts "  Total requests: #{stats[:analytics][:total_requests]}"
      puts "  Cache uptime: #{(stats[:analytics][:uptime_seconds] / 3600.0).round(2)} hours"
      puts "  Requests per second: #{stats[:analytics][:requests_per_second].round(2)}"
    end
  end
end
