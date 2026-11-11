# The live camera check: status (checking every second / finished), Stop, and the
# latest result (LocateResultComponent). Replaced on every result.
class LocatePanelComponent < ApplicationComponent
  def initialize(state:, latest:) = (@state, @latest = state, latest)

  def running? = @state&.running?
end
