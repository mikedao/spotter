# Pushes a session's current state to every open range screen (Turbo Streams over
# Solid Cable). Called after each engine event; replaces whole sections rather than
# patching pieces, so a screen opened late or reconnected is never out of step.
# The live camera picture is not among them: it refreshes itself, and replacing
# it on every shot would blank it.
class LiveBroadcast
  def initialize(session) = @session = session

  def call
    replace("session_status", SessionStatusComponent.new(session: @session))
    LivePanelComponent::SECTIONS.each do |section|
      replace("live_#{section}", LivePanelComponent.new(session: @session, section:))
    end
  end

  private
    def replace(target, component)
      Turbo::StreamsChannel.broadcast_replace_to(@session, target:, renderable: component, layout: false)
    end
end
