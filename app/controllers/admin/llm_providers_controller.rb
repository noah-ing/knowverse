# frozen_string_literal: true

module Admin
  class LlmProvidersController < BaseController
    before_action :require_admin
    
    # Shows the list of available LLM providers
    def index
      @providers = list_providers
    end
    
    # Shows the settings page for LLM providers
    def settings
      @open_ai_api_key = ENV['OPENAI_API_KEY'] || ''
      @anthropic_api_key = ENV['ANTHROPIC_API_KEY'] || ''
      @enable_local_llm = ENV['ENABLE_LOCAL_LLM'] == 'true'
      @local_llm_path = ENV['LOCAL_LLM_PATH'] || 'meta-llama/Llama-2-7b-chat-hf'
      @default_provider = ENV['DEFAULT_LLM_PROVIDER'] || 'openai'
      @default_openai_model = ENV['DEFAULT_OPENAI_MODEL'] || 'gpt-4'
      @default_anthropic_model = ENV['DEFAULT_ANTHROPIC_MODEL'] || 'claude-3-haiku-20240307'
    end
    
    # Updates the LLM provider settings
    def update
      # Update .env file
      update_env_file(
        OPENAI_API_KEY: params[:openai_api_key].presence,
        ANTHROPIC_API_KEY: params[:anthropic_api_key].presence,
        ENABLE_LOCAL_LLM: params[:enable_local_llm] == '1' ? 'true' : 'false',
        LOCAL_LLM_PATH: params[:local_llm_path].presence || 'meta-llama/Llama-2-7b-chat-hf',
        DEFAULT_LLM_PROVIDER: params[:default_provider].presence || 'openai',
        DEFAULT_OPENAI_MODEL: params[:default_openai_model].presence || 'gpt-4',
        DEFAULT_ANTHROPIC_MODEL: params[:default_anthropic_model].presence || 'claude-3-haiku-20240307'
      )
      
      # Update services/haystack/.env file
      update_haystack_env_file(
        OPENAI_API_KEY: params[:openai_api_key].presence,
        ANTHROPIC_API_KEY: params[:anthropic_api_key].presence,
        ENABLE_LOCAL_LLM: params[:enable_local_llm] == '1' ? 'true' : 'false',
        LOCAL_LLM_PATH: params[:local_llm_path].presence || 'meta-llama/Llama-2-7b-chat-hf',
        DEFAULT_LLM_PROVIDER: params[:default_provider].presence || 'openai',
        DEFAULT_OPENAI_MODEL: params[:default_openai_model].presence || 'gpt-4',
        DEFAULT_ANTHROPIC_MODEL: params[:default_anthropic_model].presence || 'claude-3-haiku-20240307'
      )
      
      # Restart the Haystack service if needed
      if params[:restart_haystack] == '1'
        restart_haystack_service
      end
      
      flash[:notice] = "LLM provider settings updated successfully."
      redirect_to admin_llm_providers_settings_path
    end
    
    # Tests a specific LLM provider
    def test
      provider = params[:provider]
      
      if provider.blank?
        flash[:error] = "Provider name is required"
        redirect_to admin_llm_providers_path
        return
      end
      
      # Get available providers
      providers_response = haystack_client.list_llm_providers
      
      # Check if the provider is available
      if !providers_response.success? || !providers_response.data.map { |p| p['name'] }.include?(provider)
        flash[:error] = "Provider #{provider} is not available"
        redirect_to admin_llm_providers_path
        return
      end
      
      # Test the provider with a simple query
      result = haystack_client.generate_answer(
        "What is KnowVerse?", 
        current_user.organizations.first.id, 
        {
          provider: provider,
          max_documents: 1,
          similarity_threshold: 0.5
        }
      )
      
      if result.success?
        flash[:notice] = "Provider #{provider} is working correctly"
      else
        flash[:error] = "Provider #{provider} test failed: #{result.error}"
      end
      
      redirect_to admin_llm_providers_path
    end
    
    private
    
    # Ensure the user is an admin
    def require_admin
      unless current_user&.admin?
        flash[:error] = "You must be an admin to access this page"
        redirect_to root_path
      end
    end
    
    # Get the list of available LLM providers
    def list_providers
      providers_response = haystack_client.list_llm_providers
      
      if providers_response.success?
        return providers_response.data.map { |p| { name: p['name'], default: p['default'] } }
      else
        flash.now[:warning] = "Unable to fetch providers: #{providers_response.error}"
        return []
      end
    end
    
    # Get an instance of the Haystack client
    def haystack_client
      @haystack_client ||= HaystackClient.new
    end
    
    # Update the .env file with new values
    def update_env_file(values)
      env_path = Rails.root.join('.env')
      
      if File.exist?(env_path)
        content = File.read(env_path)
        
        values.each do |key, value|
          if value.nil?
            # Skip nil values
            next
          elsif content.match?(/^#{key}=/)
            # Replace existing value
            content.gsub!(/^#{key}=.*$/, "#{key}=#{value}")
          else
            # Add new value at the end
            content << "\n#{key}=#{value}"
          end
        end
        
        File.write(env_path, content)
      else
        # Create new file
        content = values.compact.map { |key, value| "#{key}=#{value}" }.join("\n")
        File.write(env_path, content)
      end
      
      # Update environment variables in the current process
      values.each do |key, value|
        ENV[key.to_s] = value unless value.nil?
      end
    end
    
    # Update the Haystack .env file with new values
    def update_haystack_env_file(values)
      env_path = Rails.root.join('services', 'haystack', '.env')
      
      if File.exist?(env_path)
        content = File.read(env_path)
        
        # Make sure we have the LLM Provider section
        unless content.include?("# LLM Provider API Keys")
          content << "\n\n# LLM Provider API Keys\n"
        end
        
        # Make sure we have the LLM Configuration section
        unless content.include?("# LLM Configuration")
          content << "\n\n# LLM Configuration\n"
        end
        
        values.each do |key, value|
          if value.nil?
            # Skip nil values
            next
          elsif content.match?(/^#{key}=/)
            # Replace existing value
            content.gsub!(/^#{key}=.*$/, "#{key}=#{value}")
          elsif key.to_s.start_with?('DEFAULT_') || key.to_s == 'MAX_RAG_CONTEXT_DOCUMENTS'
            # Add new configuration value in the configuration section
            if !content.match?(/# LLM Configuration.*#{key}=/m)
              config_section = content.match(/(# LLM Configuration.*?)(\n\n|\Z)/m)
              if config_section
                replacement = "#{config_section[1]}#{key}=#{value}\n#{config_section[2]}"
                content.gsub!(/(# LLM Configuration.*?)(\n\n|\Z)/m, replacement)
              else
                # Add to the end
                content << "#{key}=#{value}\n"
              end
            end
          else
            # Add new API key value in the API keys section
            if !content.match?(/# LLM Provider API Keys.*#{key}=/m)
              api_section = content.match(/(# LLM Provider API Keys.*?)(\n\n|\Z)/m)
              if api_section
                replacement = "#{api_section[1]}#{key}=#{value}\n#{api_section[2]}"
                content.gsub!(/(# LLM Provider API Keys.*?)(\n\n|\Z)/m, replacement)
              else
                # Add to the end
                content << "#{key}=#{value}\n"
              end
            end
          end
        end
        
        File.write(env_path, content)
      end
    end
    
    # Restart the Haystack service
    def restart_haystack_service
      # This is a placeholder. In a real environment, you'd need to implement
      # logic to restart the service, possibly through a system call or API.
      # For development, this could be skipped as the service can be restarted manually.
      Rails.logger.info "PLACEHOLDER: Restarting Haystack service"
    end
  end
end
