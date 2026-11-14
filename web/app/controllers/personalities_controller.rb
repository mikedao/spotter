# Settings, "Personalities": the announcer as a character (Personality), or none.
# Choosing one starts its process in the background, so it is ready (and has
# begun rendering its likely lines) by the next session.
class PersonalitiesController < ApplicationController
  def update
    id = params[:personality].to_s.presence   # "" = none (params.expect refuses a blank)
    return redirect_to(settings_path(anchor: "voice"), alert: "That isn't one of the personalities.") if id && !Personality.valid?(id)

    Current.user.update!(personality: id)
    if id
      Personality.ensure!(id)
      notice = "Your announcer is now #{Personality.find(id).name}, from your next session."
    else
      notice = "No personality: the standard announcer, in the voice below."
    end
    redirect_to settings_path(anchor: "voice"), notice:
  end
end
