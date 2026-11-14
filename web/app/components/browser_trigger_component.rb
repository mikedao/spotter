# The range screen's microphone, for a session whose trigger is this browser
# (mic "browser", 2026-11-13: the laptop at the firing line hears the gun; the
# Mac running the engine is too far away). browser_trigger_controller.js listens
# (lib/shot_listener.js) and relays each sharp sound to the engine; this button
# shows that it is listening, and starts it again after a refusal. Beside the
# Sound button, outside everything LiveBroadcast replaces, so the microphone
# keeps running through every shot.
class BrowserTriggerComponent < ApplicationComponent
  def initialize(session:) = @session = session

  def render? = @session.live? && @session.mic == CameraProbe::BROWSER_MIC

  def call
    tag.button(type: "button", class: AnnouncerComponent::BUTTON,
               data: { controller: "browser-trigger", action: "browser-trigger#retry",
                       browser_trigger_url_value: helpers.trigger_practice_session_path(@session),
                       browser_trigger_db_value: @session.trigger_db || SoundTrigger::DB, browser_trigger_ms_value: SoundTrigger::MS,
                       browser_trigger_near_db_value: SoundTrigger::NEAR_DB,
                       browser_trigger_https_value: https_url })
  end

  private
    # Where this page is over https (a browser lets only https pages use the mic).
    def https_url
      return if request.ssl? || request.host.in?(%w[ localhost 127.0.0.1 ])

      "https://#{request.host}:#{ENV.fetch('SPOTTER_HTTPS_PORT', '3443')}#{request.fullpath}"
    end
end
