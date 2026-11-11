Rails.application.routes.draw do
  root "practice_sessions#index"

  # Sign in / out (Rails 8 authentication) and open sign-up. No password-reset
  # route: the app sends no email (bin/rails users:reset_password instead).
  get "sign_in", to: "sessions#new", as: :new_session
  resource :session, only: %i[ create destroy ]
  get "sign_up", to: "registrations#new", as: :new_registration
  post "sign_up", to: "registrations#create", as: :registration

  resources :practice_sessions, only: %i[ index show create ], path: "practice" do
    post :stop, on: :member
  end
  resources :shots, only: %i[ show update ]

  namespace :api do
    post "events", to: "events#create"
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
