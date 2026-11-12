# The wizard's sound check: the live meter, every sound heard (marked with whether
# it would trigger a capture), a summary, and the way on - Next unlocks once a
# sound would trigger, "camera only" is the escape. Replaced whole on each sound.
class ListenPanelComponent < ApplicationComponent
  def initialize(state:, user:) = (@state, @user = state, user)

  def running? = @state&.running?
  def data = @state&.data || {}
  def sounds = data["sounds"] || []
  def shots = sounds.count { it["would_trigger"] }
  def heard_a_shot? = shots.positive?
  def summary = data["summary"]
end
