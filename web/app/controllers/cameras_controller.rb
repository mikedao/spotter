# "Find cameras" on the Start form, and the preview pictures it shows.
class CamerasController < ApplicationController
  def refresh
    if (running = EngineRunner.running)
      return redirect_to practice_sessions_path, alert: "#{running.user.name}'s session is using the camera - stop it first."
    end

    probe = CameraProbe.run!
    redirect_to practice_sessions_path,
                notice: "Found #{helpers.pluralize(probe.cameras.size, 'camera')} and #{helpers.pluralize(probe.microphones.size, 'microphone')}. " \
                        "Pick the camera pointed at your target."
  rescue CameraProbe::Failed => e
    redirect_to practice_sessions_path, alert: "Couldn't look for cameras: #{e.message}"
  end

  def preview
    path = CameraProbe.preview_path(params[:index])
    return head :not_found unless path

    send_file path, type: "image/jpeg", disposition: "inline"
  rescue ArgumentError
    head :not_found
  end
end
