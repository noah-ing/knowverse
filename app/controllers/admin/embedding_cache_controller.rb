module Admin
  class EmbeddingCacheController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_admin

    # Dashboard page showing overall cache statistics
    def dashboard
      # Get cache manager
      @cache_manager = EmbeddingCache::CacheManager.instance
      
      # Get overall statistics
      @stats = @cache_manager.stats
      
      # Get statistics for all organizations (for admin view)
      @organizations = Organization.all.map do |org|
        {
          id: org.id,
          name: org.name,
          stats: @cache_manager.organization_stats(org.id)
        }
      end
    end
    
    # Organization-specific cache details
    def organization
      # Get organization
      @organization = Organization.find(params[:id])
      
      # Get cache manager
      @cache_manager = EmbeddingCache::CacheManager.instance
      
      # Get organization-specific statistics
      @stats = @cache_manager.organization_stats(@organization.id)
      
      # Get domain information
      @domains = []
      if @stats[:redis][:domains].present?
        @domains = @stats[:redis][:domains].map do |domain_data|
          domain_name = domain_data[:domain]
          
          # Try to get confidence score for this domain
          confidence_score = DomainConfidenceScore.where(
            organization_id: @organization.id,
            domain: domain_name
          ).order(created_at: :desc).first
          
          {
            name: domain_name,
            count: domain_data[:count],
            confidence: confidence_score&.score || 0
          }
        end
      end
    end
    
    # Warm the cache for an organization
    def warm
      # Get organization
      organization_id = params[:organization_id]
      
      # Get parameters
      source = params[:source] || 'popular_queries'
      limit = (params[:limit] || 100).to_i
      
      # Enqueue cache warming jobs
      cache_manager = EmbeddingCache::CacheManager.instance
      count = cache_manager.warm_cache(
        organization_id,
        source: source.to_sym,
        limit: limit,
        models: params[:models] || ['base']
      )
      
      # Flash message
      flash[:notice] = "Cache warming started: #{count} queries enqueued for processing"
      
      # Redirect back to dashboard
      redirect_to admin_embedding_cache_dashboard_path
    end
    
    # Clear the cache for an organization
    def clear
      # Get organization
      organization_id = params[:organization_id]
      
      # Clear cache
      cache_manager = EmbeddingCache::CacheManager.instance
      cache_manager.clear_organization(organization_id)
      
      # Flash message
      flash[:notice] = "Cache cleared for organization ID #{organization_id}"
      
      # Redirect back to dashboard
      redirect_to admin_embedding_cache_dashboard_path
    end
    
    private
    
    def ensure_admin
      unless current_user.admin?
        flash[:alert] = "You must be an administrator to access this page"
        redirect_to root_path
      end
    end
  end
end
