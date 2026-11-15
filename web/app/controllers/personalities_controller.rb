# Settings, "Personalities": the announcer as a character (Personality), or none.
class PersonalitiesController < ApplicationController
  def update
    id = params[:personality].to_s.presence   # "" = none (params.expect refuses a blank)
    return redirect_to(settings_path(anchor: "voice"), alert: "That isn't one of the personalities.") if id && !Personality.valid?(id)

    Current.user.update!(personality: id)
    notice = if id then "Your announcer is now #{Personality.find(id).name}, from your next session."
    else "No personality: the standard announcer, in the voice below."
    end
    redirect_to settings_path(anchor: "voice"), notice:
  end
end
