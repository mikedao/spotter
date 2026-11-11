# Rig setup: the camera check (locate) and the sound check (listen), in the
# browser instead of a terminal.
class SetupsController < ApplicationController
  def show
    @probe = CameraProbe.latest
    @locate = RigCheck::Locate.latest(Current.user)
    @locate_state = RigCheck::Locate.state_for(Current.user)
    @listen = RigCheck::Listen.state_for(Current.user)
    @camera = Current.user.last_camera.presence || EngineRunner.camera
    @mic = Current.user.last_mic.presence || EngineRunner.mic
  end

  def locate
    camera = params[:camera] == "url" ? params[:camera_url] : params[:camera]
    RigCheck::Locate.start!(user: Current.user, camera: camera.to_s.strip, target: params[:target].presence || "pistol")
    Current.user.update!(last_camera: camera.to_s.strip)
    redirect_to setup_path(anchor: "camera")
  rescue RigCheck::Busy, EngineRunner::BadCamera, ArgumentError => e
    redirect_to setup_path(anchor: "camera"), alert: "Camera check: #{e.message}."
  end

  def stop_locate
    RigCheck::Locate.stop!(Current.user)
    redirect_to setup_path(anchor: "camera")
  end

  def locate_overlay
    path = RigCheck::Locate.overlay_path(Current.user)
    path.exist? ? send_file(path, type: "image/png", disposition: "inline") : head(:not_found)
  end

  def listen
    RigCheck::Listen.start!(user: Current.user, mic: params[:mic], seconds: params[:seconds])
    Current.user.update!(last_mic: params[:mic].to_s.strip)
    redirect_to setup_path(anchor: "sound")
  rescue RigCheck::Busy, EngineRunner::BadCamera => e
    redirect_to setup_path(anchor: "sound"), alert: "Sound check: #{e.message}."
  end

  def stop_listen
    RigCheck::Listen.stop!(Current.user)
    redirect_to setup_path(anchor: "sound")
  end
end
