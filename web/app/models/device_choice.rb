# What the camera and microphone pickers offer, and what they pre-select: only
# devices the last "Find cameras and microphones" actually found (CameraProbe),
# plus a stream URL and camera-only - never a remembered or default device that
# isn't there now (the rig's Kiyo unplugged, a phone gone home).
#
#   choice = DeviceChoice.new(user: Current.user)
#   choice.cameras      # what the probe found
#   choice.camera       # "1", a stream URL, or nil (nothing to pick yet)
#   choice.mic          # a found microphone's name, or CameraProbe::NO_MIC
class DeviceChoice
  attr_reader :probe

  def initialize(user:, probe: CameraProbe.latest)
    @user = user
    @probe = probe
  end

  def cameras = probe&.cameras || []
  def microphones = probe&.microphones || []
  def pairs = probe&.pairs || {}
  def found? = probe.present?

  # The camera used last, if it is still there (or is a stream URL, which the
  # probe can't check); else the rig's SPOTTER_CAMERA on the same terms; else
  # the first one found.
  def camera
    [ @user.last_camera, EngineRunner.camera ].compact_blank.map(&:to_s)
      .find { url?(it) || listed_camera?(it) } || cameras.first&.value
  end

  def camera_url? = url?(camera)

  # The mic used last, if it is still there (or "none"); else the chosen
  # camera's own; else the rig's SPOTTER_MIC if found; else camera only.
  def mic
    names = microphones.map(&:name)
    last = @user.last_mic.to_s
    return last if [ CameraProbe::NO_MIC, CameraProbe::BROWSER_MIC ].include?(last) || names.include?(last)

    pairs[camera].presence || ([ EngineRunner.mic ] & names).first || CameraProbe::NO_MIC
  end

  private
    def url?(value) = value.to_s.include?("://")
    def listed_camera?(value) = cameras.any? { it.value == value }
end
