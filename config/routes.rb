Rails.application.routes.draw do
  # Health check endpoint for container orchestration
  get '/health', to: 'health#show'

  # Prometheus metrics endpoint (protected by IP in production)
  get '/metrics', to: 'metrics#index'

  # MCP (Model Context Protocol) endpoints for Claude Desktop integration
  scope '/mcp', defaults: { format: :json } do
    get 'tools', to: 'mcp#tools'
    post 'execute', to: 'mcp#execute'
    get 'resources', to: 'mcp#resources'
    get 'resource', to: 'mcp#resource'
  end

  root 'home#index'
  get 'dashboard', to: 'home#dashboard'

  # Static pages
  get '/privacy', to: 'pages#privacy', as: :privacy
  get '/terms', to: 'pages#terms', as: :terms
  get '/cookies', to: 'pages#cookies', as: :cookies
  get '/docs', to: 'pages#documentation', as: :documentation

  # Convenience routes that redirect to organization-scoped resources
  get '/documents', to: 'documents#index', as: :documents_root
  get '/rag', to: 'rag#index', as: :rag_root
  get '/conversations', to: 'conversations#index', as: :conversations_root
  
  # Organization and document routes
  resources :organizations do
    member do
      get :dashboard, as: :dashboard
      get :settings
      post :invite_user
      post :regenerate_api_key
    end

    # Billing & Subscription management (owner-only)
    resource :subscription, only: [:show, :new, :create, :update], controller: 'organizations/subscriptions' do
      patch :cancel
      patch :resume
      post :start_trial
      get :portal
    end

    # SSO Configuration (for org admins)
    resource :sso_config, only: [:show, :new, :create, :edit, :update, :destroy] do
      post :test
    end

    # Connectors for external document sources
    namespace :connectors do
      resource :google_drive, only: [:new, :create, :show, :destroy], controller: 'google_drive' do
        get :callback
        post :sync
      end

      resource :notion, only: [:new, :create, :show, :destroy], controller: 'notion' do
        get :callback
        post :sync
      end

      resource :github, only: [:new, :create, :show, :destroy], controller: 'github' do
        get :callback
        post :sync
      end

      resource :slack, only: [:new, :create, :show, :destroy], controller: 'slack' do
        get :callback
        post :sync
      end

      resource :confluence, only: [:new, :create, :show, :destroy], controller: 'confluence' do
        get :callback
        post :sync
      end
    end

    # Document routes nested under organizations
    resources :documents do
      collection do
        post :upload
        get :search
        delete :bulk_destroy
      end
      
      member do
        get :status
        get :content
        post :start_processing
        post :retry_processing
      end
    end
    
    # Vector visualization routes
    resources :vectors, only: [:index] do
      collection do
        get :projections
        post :reduce
        get :clusters
        post :cluster
      end
    end
    
    # RAG (Retrieval Augmented Generation) routes
    resources :rag, only: [:index] do
      collection do
        post :answer
        get :answer # Support GET for form submission
        get :stream  # Streaming endpoint for SSE
        post :stream # Support POST for streaming endpoint
        get :conversation # Get conversation history
        # Agentic RAG endpoints
        get :agent_stream  # Agentic RAG streaming endpoint
        post :agent_stream # Support POST for agent streaming
        get :agent_info    # Get available agent modes and tools
      end
    end
    
    # Conversation management
    resources :conversations do
      collection do
        post :find_or_create
      end
      
      resources :messages, only: [:create, :index], controller: 'conversation_messages' do
        collection do
          post :bulk_create
        end
      end
    end
  end
  
  # Search routes - fix namespace issue with Search::SearchController
  # Main search route
  get '/search', to: 'search#index', as: :search
  post '/search/query', to: 'search#query', as: :search_query
  get '/search/query', to: 'search#query'  # Support GET for form submission
  get '/search/results/:id', to: 'search#results', as: :results_search
  get '/search/streaming', to: 'search#streaming', as: :basic_search_streaming

  # Namespaced search routes  
  namespace :search do
    # Streaming search endpoints for SSE
    get '/streaming', to: 'streaming#stream', as: :streaming
    post '/streaming', to: 'streaming#stream', as: :streaming_post
    
    # Component initialization endpoint
    get '/components/initialize', to: 'streaming#initialize_components', as: :initialize_components
    
    # Search feedback routes
    resources :feedbacks, only: [:create], controller: 'search_feedbacks'
    post '/thumbs_up/:search_query_id/:document_id', to: 'search_feedbacks#thumbs_up', as: :thumbs_up
    post '/thumbs_down/:search_query_id/:document_id', to: 'search_feedbacks#thumbs_down', as: :thumbs_down
  end

  # Devise authentication routes with OmniAuth callbacks
  devise_for :users, controllers: {
    omniauth_callbacks: 'users/omniauth_callbacks'
  }

  devise_scope :user do
    post '/users/magic_link', to: 'users/magic_links#create', as: :create_user_magic_link
    get '/users/magic_link/:login_token', to: 'users/magic_links#show', as: :custom_user_magic_link
    get '/users/sign_out', to: 'devise/sessions#destroy'
  end

  # SSO (Single Sign-On) routes
  get '/sso', to: 'sso#index', as: :sso
  post '/sso/lookup', to: 'sso#lookup', as: :sso_lookup
  get '/sso/:org_slug', to: 'sso#login', as: :sso_login
  post '/sso/:org_slug/initiate', to: 'sso#initiate', as: :sso_initiate

  # OmniAuth callback routes (org-specific paths)
  get '/auth/saml/:org_slug/callback', to: 'users/omniauth_callbacks#saml'
  post '/auth/saml/:org_slug/callback', to: 'users/omniauth_callbacks#saml'
  get '/auth/openid_connect/:org_slug/callback', to: 'users/omniauth_callbacks#openid_connect'
  
  # User profile customization routes
  namespace :users do
    resource :profile, only: [:show, :edit, :update]
    resource :preferences, only: [:show, :update]
    resource :account, only: [:show, :update, :destroy]
    resource :usage, only: [:show]
  end
  
  # API routes (v1)
  namespace :api, defaults: { format: :json } do
    namespace :v1 do
      resources :organizations, only: [] do
        resources :bulk_uploads, only: [:index, :show, :create, :destroy] do
          member do
            post :add_files
            post :start
          end
        end
      end
    end
  end

  # Admin routes
  namespace :admin do
    get '/', to: 'dashboard#index', as: :dashboard

    # Mission Control - NASA-style dashboard
    get 'mission_control', to: 'mission_control#index', as: :mission_control
    get 'mission_control/status', to: 'mission_control#status', as: :mission_control_status
    
    # Embedding cache management
    get 'embedding_cache/dashboard', to: 'embedding_cache#dashboard', as: :embedding_cache_dashboard
    get 'embedding_cache/organization/:id', to: 'embedding_cache#organization', as: :embedding_cache_organization
    post 'embedding_cache/warm', to: 'embedding_cache#warm', as: :embedding_cache_warm
    delete 'embedding_cache/clear', to: 'embedding_cache#clear', as: :embedding_cache_clear
    
    # Search metrics and feedback
    resources :search_metrics, only: [:index] do
      collection do
        get :provider_comparison
        get :feedback_analysis
        get :problem_queries
      end
    end
    
    # Analytics routes
    resource :analytics, only: [:show], controller: 'analytics' do
      collection do
        get :events
        get :user_activity
      end
    end
    # Add a direct route for the index action
    get 'analytics', to: 'analytics#index', as: :analytics_index
    
    resources :users do
      member do
        patch :update_subscription
        patch :deactivate
        patch :reactivate
        post :send_magic_link
      end
      collection do
        get :search
      end
    end
    
    # Distributed system management
    get 'distributed/dashboard', to: 'distributed#dashboard', as: :distributed_dashboard
    get 'distributed/status', to: 'distributed#status', as: :distributed_status
    post 'distributed/add_node', to: 'distributed#add_node', as: :distributed_add_node
    delete 'distributed/remove_node', to: 'distributed#remove_node', as: :distributed_remove_node
    post 'distributed/snapshot', to: 'distributed#snapshot', as: :distributed_snapshot
    post 'distributed/rollback', to: 'distributed#rollback', as: :distributed_rollback
    
    # LLM Provider management
    get 'llm_providers', to: 'llm_providers#index', as: :llm_providers
    get 'llm_providers/settings', to: 'llm_providers#settings', as: :llm_providers_settings
    patch 'llm_providers/update', to: 'llm_providers#update', as: :update_llm_providers
    post 'llm_providers/test', to: 'llm_providers#test', as: :test_llm_provider
    
    # Domain-specific embeddings management
    resources :organizations, only: [] do
      resources :domain_embedding_models do
        member do
          post :toggle_active
          post :retrain
        end
        collection do
          post :generate_embeddings
        end
      end
      
      # Organization template management
      resources :organization_templates do
        member do
          post :set_default
          get :test
          get :analytics
        end
      end
    end
    
    # Domain confidence threshold management
    resources :domain_confidence, only: [:index, :show] do
      member do
        get :settings
        patch :update_settings
        get :test
      end
    end
  end

  # Stripe webhooks endpoint
  post '/webhooks/stripe', to: 'webhooks#stripe'
  
  # Subscription management routes
  namespace :subscriptions do
    # Plans routes
    get '/', to: 'plans#index'
    get '/plans', to: 'plans#index'
    get '/plans/:id', to: 'plans#show', as: :plan
    post '/plans/:plan_id/subscribe', to: 'plans#create', as: :subscribe
    
    # Payment methods routes
    get '/payment_methods', to: 'payment_methods#index'
    get '/payment_methods/new', to: 'payment_methods#new'
    post '/payment_methods', to: 'payment_methods#create'
    delete '/payment_methods/:id', to: 'payment_methods#destroy'
    
    # Subscription management routes
    get '/subscription', to: 'subscriptions#show', as: :subscription
    patch '/subscription/cancel', to: 'subscriptions#cancel', as: :cancel_subscription
    patch '/subscription/resume', to: 'subscriptions#resume', as: :resume_subscription
  end
end
