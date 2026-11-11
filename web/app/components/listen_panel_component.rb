# The sound check's panel: the live meter, every sound heard (marked with whether
# it would trigger a capture), then a summary. Replaced whole on each sound.
class ListenPanelComponent < ApplicationComponent
  def initialize(state:, user:) = (@state, @user = state, user)

  def running? = @state&.running?
  def data = @state&.data || {}
  def sounds = data["sounds"] || []
  def shots = sounds.count { it["would_trigger"] }
  def summary = data["summary"]
end
