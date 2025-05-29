# frozen_string_literal: true

module VectorSearch
  # SearchComponentManager is a singleton that manages the lifecycle of search components.
  # It provides lazy loading of components, thread-safe access, and configuration management.
  #
  # The manager acts as a registry for various component types and is responsible for
  # creating and managing ComponentBridge instances for different domain models and organizations.
  #
  class SearchComponentManager
    include Singleton
    
    # Initialize the component manager
    def initialize
      @component_registry = {}
      @bridges = {}
      @config = {}
      @mutex = Mutex.new
      
      register_default_components
    end
    
    # Get a ComponentBridge for a specific domain model and organization
    # @param domain_model [DomainEmbeddingModel, nil] The domain embedding model to use
    # @param organization [Organization, nil] The organization context
    # @param user [User, nil] The user context
    # @param options [Hash] Additional options to pass to the bridge
    # @return [VectorSearch::ComponentBridge] The component bridge instance
    def bridge_for(domain_model: nil, organization: nil, user: nil, options: {})
      # Generate a unique key for this bridge based on domain model and organization
      key = bridge_key(domain_model, organization)
      
      # Thread-safe access to the bridges hash
      @mutex.synchronize do
        # Return existing bridge if it exists and is valid
        if @bridges[key] && bridge_valid?(@bridges[key])
          return @bridges[key]
        end
        
        # Create a new bridge if none exists or the existing one is invalid
        @bridges[key] = ComponentBridge.new(
          domain_model: domain_model,
          organization: organization,
          user: user,
          options: options
        )
      end
    end
    
    # Register a component type with the manager
    # @param type [Symbol] The component type identifier
    # @param component_class [Class] The component class
    # @return [Boolean] Whether registration was successful
    def register_component(type, component_class)
      @mutex.synchronize do
        @component_registry[type.to_sym] = component_class
        true
      end
    end
    
    # Get a registered component class
    # @param type [Symbol] The component type identifier
    # @return [Class, nil] The component class, or nil if not registered
    def component_class(type)
      @component_registry[type.to_sym]
    end
    
    # Set configuration for the manager
    # @param config [Hash] Configuration hash
    def configure(config = {})
      @mutex.synchronize do
        @config.merge!(config)
      end
    end
    
    # Get configuration value
    # @param key [Symbol] Configuration key
    # @param default [Object] Default value if key not found
    # @return [Object] Configuration value
    def config(key, default = nil)
      @config.fetch(key.to_sym, default)
    end
    
    # Cleanup idle bridges and components to free memory
    # @param max_idle_time [ActiveSupport::Duration] Maximum idle time
    def cleanup_idle(max_idle_time = 1.hour)
      @mutex.synchronize do
        current_time = Time.current
        
        # Cleanup idle bridges
        @bridges.each_value do |bridge|
          bridge.cleanup_idle_components(max_idle_time, current_time)
        end
        
        # Remove idle bridges
        @bridges.delete_if do |_, bridge|
          bridge.components.empty? && (current_time - bridge.last_access_time) > max_idle_time
        end
      end
    end
    
    # Get all registered component types
    # @return [Array<Symbol>] List of component types
    def component_types
      @component_registry.keys
    end
    
    # Get statistics about the manager
    # @return [Hash] Statistics hash
    def stats
      @mutex.synchronize do
        {
          registered_components: @component_registry.keys.count,
          active_bridges: @bridges.count,
          total_components: @bridges.sum { |_, bridge| bridge.components.count },
          config: @config
        }
      end
    end
    
    private
    
    # Generate a unique key for a bridge
    # @param domain_model [DomainEmbeddingModel, nil] The domain model
    # @param organization [Organization, nil] The organization
    # @return [String] Unique key
    def bridge_key(domain_model, organization)
      domain_id = domain_model&.id || 'default'
      org_id = organization&.id || 'global'
      
      "domain_#{domain_id}_org_#{org_id}"
    end
    
    # Check if a bridge is still valid
    # @param bridge [VectorSearch::ComponentBridge] The bridge to check
    # @return [Boolean] Whether the bridge is valid
    def bridge_valid?(bridge)
      # Check if bridge is still valid (e.g., its references are still valid)
      # For now, just check if it's not nil
      !bridge.nil?
    end
    
    # Register default component types
    def register_default_components
      # These would be defined elsewhere in the codebase
      # register_component(:search_form, SearchFormComponent)
      # register_component(:results_list, ResultsListComponent)
      # register_component(:filter_panel, FilterPanelComponent)
    end
  end
end
