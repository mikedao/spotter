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

  resources :practice_sessions, only: %i[ index show create update destroy ], path: "practice" do
    post :stop, on: :member
    patch :diary, on: :member        # the session diary: exercises, problems, fixes, learned
    post :start_match, on: :member   # end a match's sighting time early
    get :camera, on: :member   # the live camera picture, relayed from the engine
    resource :shotmetrix, only: :show, controller: "shotmetrix"   # the session as Shotmetrix QR codes
    resource :report, only: :show   # the session as a printable report (Save as PDF)
    resources :cards, only: :show, param: :number   # any card of the session, its shots deletable
  end
  resources :shots, only: %i[ show update destroy ] do
    post :pinpoint, on: :member   # score a capture by tapping its hole
    get :plot, on: :member        # ...in a panel over the live range screen
  end

  # The journal: trends across sessions, against the shooter's goal.
  resource :journal, only: %i[ show update ] do
    get :report   # the journal as a printable progress report (Save as PDF)
  end

  # Gear: the shooter's guns and pellets (one per lot), picked per session.
  get "gear", to: "gear#show", as: :gear
  resources :guns, only: %i[ new create show edit update ]
  resources :pellets, only: %i[ new create edit update ]

  # Settings: the announcer voice (pick one, hear each one's sample).
  get "settings", to: "settings#show", as: :settings
  patch "settings", to: "settings#update"
  patch "settings/chatty", to: "settings#chatty", as: :chatty_setting   # the range screen's Chatty button
  resource :voice, only: :update
  get "voices/:id/sample", to: "voices#sample", as: :voice_sample
  get "voices/:id/piece", to: "voices#piece", as: :voice_piece   # ?text=shot%204: one announcement piece

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
