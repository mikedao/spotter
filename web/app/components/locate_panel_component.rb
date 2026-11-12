# The wizard's live camera check: status (checking every second / finished),
# Stop, the latest result (LocateResultComponent), and the way on - Next
# unlocks at "Ready to shoot", "Continue anyway" is the escape. Replaced on
# every result, so Next unlocks the moment the check passes.
class LocatePanelComponent < ApplicationComponent
  def initialize(state:, latest:) = (@state, @latest = state, latest)

  def running? = @state&.running?
  def ready? = @latest&.ok?
end
