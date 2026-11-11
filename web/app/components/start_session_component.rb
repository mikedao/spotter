# Start a practice session: pick the camera (by its preview picture), the target,
# and how many shots go on a card; the web app launches the engine
# (EngineRunner). While anyone's session runs it says who is shooting instead -
# one camera, one session at a time. Lists only the cameras and microphones the
# last device search found (DeviceChoice), plus a stream URL and camera only.
class StartSessionComponent < ApplicationComponent
  def initialize(running:, user:, choice: DeviceChoice.new(user:))
    @running, @user, @choice = running, user, choice
  end

  def cameras = @choice.cameras
  def pairs = @choice.pairs
  def probe = @choice.probe
  def chosen = @choice.camera.to_s
  def chosen_url? = @choice.camera_url?
  def chosen_mic = @choice.mic

  def mic_options
    @choice.microphones.map { [ it.name, it.value ] } +
      [ [ "No microphone - camera only (slower: 2-4 s per shot)", CameraProbe::NO_MIC ] ]
  end
end
