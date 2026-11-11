# The sound check's live panel: every sound the microphone hears, marked with
# whether it would trigger a capture, then a summary. Replaced whole on each
# event (RigCheck::Listen broadcasts it).
class ListenPanelComponent < ApplicationComponent
  def initialize(state:, user:) = (@state, @user = state, user)

  def running? = @state && !@state.finished
end
