# The announcer voice: each shooter picks theirs in Settings, and the range
# screen plays every announcement in it, piece by piece (Voice, ../engine/voice).
class VoicesController < ApplicationController
  def update
    id = params.expect(:voice).to_s
    return redirect_to(settings_path(anchor: "voice"), alert: "That isn't one of the voices.") unless Voice.valid?(id)

    Current.user.update!(voice: id)
    Voice.prewarm!(id)   # every piece it can say, in the background, for the next session
    redirect_to settings_path(anchor: "voice"), notice: "Your announcer is now #{Voice.find(id).name}. It's used from your next session."
  end

  # One piece of an announcement ("shot 4", "9.6") in a voice, for the range
  # screen to play: cached, or rendered on first use. The same text always
  # sounds the same, so the browser may keep it.
  def piece
    path = Voice.piece!(params[:id], params[:text].to_s)
    response.headers["Cache-Control"] = "private, max-age=604800"
    send_file path, type: "audio/wav", disposition: "inline"
  rescue ArgumentError
    head :not_found
  rescue Voice::Failed => e
    render plain: e.message, status: :service_unavailable
  end

  # A WAV of the voice reading the sample announcements (made on first request).
  def sample
    path = Voice.sample_path(params[:id])
    send_file path, type: path.extname == ".m4a" ? "audio/mp4" : "audio/wav", disposition: "inline"
  rescue ArgumentError
    head :not_found
  rescue Voice::Failed => e
    render plain: e.message, status: :service_unavailable
  end
end
