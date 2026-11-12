# "Look again" on the new-session wizard's camera step, and the preview
# pictures it shows.
class CamerasController < ApplicationController
  def refresh
    back = params[:back] == "setup" ? setup_camera_path : practice_sessions_path
    if (running = EngineRunner.running)
      return redirect_to back, alert: "#{running.user.name}'s session is using the camera - stop it first."
    end

    RigCheck.stop_for!(Current.user)   # a camera check holds the camera
    probe = CameraProbe.run!
    redirect_to back,
                notice: "Found #{helpers.pluralize(probe.cameras.size, 'camera')} and #{helpers.pluralize(probe.microphones.size, 'microphone')}. " \
                        "Pick the camera pointed at your target."
  rescue CameraProbe::Failed => e
    redirect_to back, alert: "Couldn't look for cameras: #{e.message}"
  end

  def preview
    path = CameraProbe.preview_path(params[:index])
    return head :not_found unless path

    send_file path, type: "image/jpeg", disposition: "inline"
  rescue ArgumentError
    head :not_found
  end
end
