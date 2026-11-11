# Start a practice session: pick the camera (by its preview picture), the target,
# and how many shots go on a card; the web app launches the engine
# (EngineRunner). While anyone's session runs it says who is shooting instead -
# one camera, one session at a time.
class StartSessionComponent < ApplicationComponent
  def initialize(running:, user:, probe: CameraProbe.latest)
    @running, @user, @probe = running, user, probe
  end

  def cameras = @probe&.cameras || []

  # Pre-select the camera used last, else the rig's default.
  def chosen = (@user.last_camera.presence || EngineRunner.camera).to_s
  def chosen_url? = chosen.include?("://")
  def default_listed? = cameras.any? { it.value == chosen }
end
