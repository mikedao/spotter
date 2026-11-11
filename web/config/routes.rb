Rails.application.routes.draw do
  root "practice_sessions#index"

  resources :practice_sessions, only: %i[ index show ], path: "sessions"
  resources :shots, only: %i[ show update ]

  namespace :api do
    post "events", to: "events#create"
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
