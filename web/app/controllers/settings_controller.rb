# Settings: the announcer voice (VoicePickerComponent) and what it says
# (diagnostic mode).
class SettingsController < ApplicationController
  def show
  end

  # Diagnostic mode: also say why a shot is worth a look (line call, overlaps a
  # hole, found without a sound...). Applies to announcements from now on.
  def update
    on = ActiveModel::Type::Boolean.new.cast(params.dig(:user, :diagnostic_announcements))
    Current.user.update!(diagnostic_announcements: on)
    redirect_to settings_path(anchor: "announcements"), notice: "Diagnostic mode is #{on ? 'on' : 'off'}."
  end
end
