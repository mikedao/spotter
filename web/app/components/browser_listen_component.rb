# The wizard's sound check when THIS BROWSER is the microphone (2026-11-13): the
# same check as ListenPanelComponent - a live meter against the room's floor with
# the trigger level marked, each sound marked "would trigger" or not, Next once a
# shot would trigger, camera only as the escape - but run in the page
# (browser_listen_controller.js, lib/shot_listener.js: the engine's detector,
# ported), at the engine's own trigger rule (SoundTrigger). A shot it hears is
# reported to SessionSetupController#heard and remembered.
class BrowserListenComponent < ApplicationComponent
  SCALE_MAX = 90.0   # the meter's full width, dB over the room

  def initialize(level:) = @level = level

  attr_reader :level

  def trigger_pct = (level / SCALE_MAX * 100).round

  def https_url
    return if request.ssl? || request.host.in?(%w[ localhost 127.0.0.1 ])

    "https://#{request.host}:#{ENV.fetch('SPOTTER_HTTPS_PORT', '3443')}#{request.fullpath}"
  end
end
