# Settings: the announcer voice (VoicePickerComponent) and what it says -
# diagnostic mode and chatty mode.
class SettingsController < ApplicationController
  def show
  end

  # Diagnostic mode (also say why a shot is worth a look) and chatty mode (the
  # announcer comments: streaks, bests, pace, summaries). From now on.
  def update
    Current.user.update!(params.expect(user: [ :diagnostic_announcements, :chatty ]))
    redirect_to settings_path(anchor: "announcements"), notice: "Saved what the announcer says."
  end

  # The range screen's Chatty button: on or off at will, mid-session, without a
  # page load (which would turn the sound off).
  def chatty
    Current.user.update!(chatty: ActiveModel::Type::Boolean.new.cast(params[:chatty]))
    render json: { chatty: Current.user.chatty }
  end
end
