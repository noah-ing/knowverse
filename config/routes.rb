Rails.application.routes.draw do
  root 'home#index'
  get 'dashboard', to: 'home#dashboard'

  devise_for :users

  devise_scope :user do
    post '/users/magic_link', to: 'users/magic_links#create', as: :create_user_magic_link
  end

  # ✨ Mount the letter_opener_web UI in development
  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end
end
