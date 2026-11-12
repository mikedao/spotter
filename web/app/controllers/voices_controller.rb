# The announcer voice: each shooter picks theirs in Settings; the engine speaks
# every announcement in it (Voice, ../engine/voice).
class VoicesController < ApplicationController
  def update
    id = params.expect(:voice).to_s
    return redirect_to(settings_path(anchor: "voice"), alert: "That isn't one of the voices.") unless Voice.valid?(id)

    Current.user.update!(voice: id)
    Voice.prewarm!(id)   # every piece it can say, in the background, for the next session
    redirect_to settings_path(anchor: "voice"), notice: "Your announcer is now #{Voice.find(id).name}. It's used from your next session."
  end

  # A WAV of the voice reading the sample announcements (made on first request).
  def sample
    send_file Voice.sample_path(params[:id]), type: "audio/wav", disposition: "inline"
  rescue ArgumentError
    head :not_found
  rescue Voice::Failed => e
    render plain: e.message, status: :service_unavailable
  end
end
