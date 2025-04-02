Rails.application.routes.draw do
  root 'home#index'
  get 'dashboard', to: 'home#dashboard'

  devise_for :users

  devise_scope :user do
    post '/users/magic_link', to: 'users/magic_links#create', as: :create_user_magic_link
    get '/users/magic_link/:login_token', to: 'users/magic_links#show', as: :custom_user_magic_link
    get '/users/sign_out', to: 'devise/sessions#destroy'
  end
  
  # User profile customization routes
  namespace :users do
    resource :profile, only: [:show, :edit, :update]
    resource :preferences, only: [:show, :update]
    resource :account, only: [:show, :update, :destroy]
    resource :usage, only: [:show]
  end
  
  # Admin routes
  namespace :admin do
    get '/', to: 'dashboard#index', as: :dashboard
    
    # Analytics routes
    resource :analytics, only: [:index], controller: 'analytics' do
      collection do
        get :events
        get :user_activity
      end
    end
    
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
