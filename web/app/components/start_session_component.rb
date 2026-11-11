# Start a practice session: pick the camera (by its preview picture), the target,
# and how many shots go on a card; the web app launches the engine
# (EngineRunner). While anyone's session runs it says who is shooting instead -
# one camera, one session at a time.
class StartSessionComponent < ApplicationComponent
  def initialize(running:, user:, probe: CameraProbe.latest)
    @running, @user, @probe = running, user, probe
  end

  def cameras = @probe&.cameras || []
  def microphones = @probe&.microphones || []
  def pairs = @probe&.pairs || {}

  # Pre-select the camera used last, else the rig's default.
  def chosen = (@user.last_camera.presence || EngineRunner.camera).to_s
  def chosen_url? = chosen.include?("://")
  def default_listed? = cameras.any? { it.value == chosen }

  # The mic used last, else the chosen camera's own, else the rig's default.
  def chosen_mic = (@user.last_mic.presence || pairs[chosen].presence || EngineRunner.mic).to_s

  # [label, value] for the microphone menu: what the probe found, the current
  # choice if it wasn't found (e.g. the Kiyo while unplugged), and camera only.
  def mic_options
    names = microphones.map(&:name)
    names.unshift(chosen_mic) unless names.include?(chosen_mic) || chosen_mic == CameraProbe::NO_MIC
    names.map { [ it, it ] } + [ [ "No microphone - camera only (slower: 2-4 s per shot)", CameraProbe::NO_MIC ] ]
  end
end
