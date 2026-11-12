Rails.application.routes.draw do
  root "practice_sessions#index"

  # Sign in / out (Rails 8 authentication) and open sign-up. No PIN-reset
  # route: the app sends no email (bin/rails users:reset_pin instead).
  get "sign_in", to: "sessions#new", as: :new_session
  resource :session, only: %i[ create destroy ]
  get "sign_up", to: "registrations#new", as: :new_registration
  post "sign_up", to: "registrations#create", as: :registration

  # New session: a setup wizard every time - camera, camera check, microphone
  # and sound check, then start. Before `practice/:id` so "new" isn't an id.
  scope "practice/new", controller: "session_setup", as: "setup" do
    post "/", action: :create, as: ""                       # find devices, then step 1
    get "camera", action: :camera, as: :camera
    post "camera", action: :choose_camera
    get "check", action: :check, as: :check
    post "check", action: :recheck
    post "check/stop", action: :stop_check, as: :stop_check
    get "check/overlay", action: :overlay, as: :overlay
    get "microphone", action: :microphone, as: :microphone
    post "microphone", action: :listen
    post "microphone/stop", action: :stop_listen, as: :stop_listen
    get "start", action: :start, as: :start
  end

  resources :practice_sessions, only: %i[ index show create destroy ], path: "practice" do
    post :stop, on: :member
    get :camera, on: :member   # the live camera picture, relayed from the engine
  end
  resources :shots, only: %i[ show update ]

  # Settings: the announcer voice (pick one, hear each one's sample).
  get "settings", to: "settings#show", as: :settings
  resource :voice, only: :update
  get "voices/:id/sample", to: "voices#sample", as: :voice_sample

  # The wizard's camera step: look again, and each camera's preview picture.
  post "cameras/refresh", to: "cameras#refresh", as: :refresh_cameras
  get "cameras/:index/preview", to: "cameras#preview", as: :camera_preview, constraints: { index: /\d+/ }

  namespace :api do
    post "events", to: "events#create"
  end

  get "up" => "rails/health#show", as: :rails_health_check

  # Installable as an app (its own window, no browser tabs or address bar).
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
end
