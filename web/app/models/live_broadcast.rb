# Pushes a session's current state to every open range screen (Turbo Streams over
# Solid Cable). Called after each engine event; replaces whole panels rather than
# patching pieces, so a screen opened late or reconnected is never out of step.
class LiveBroadcast
  def initialize(session) = @session = session

  def call
    Turbo::StreamsChannel.broadcast_replace_to(
      @session, target: "session_status", renderable: SessionStatusComponent.new(session: @session), layout: false
    )
    Turbo::StreamsChannel.broadcast_replace_to(
      @session, target: "live_panel", renderable: LivePanelComponent.new(session: @session), layout: false
    )
  end
end
