# What the training plan set for this session: the block it was started for (Slow
# groups, Called shots...), its instructions and shot count, as a collapsed line
# on the session page, so the plan is in front of you while you shoot. Static: the
# live panels beside it keep the count.
class PlanBlockComponent < ApplicationComponent
  def initialize(session:) = @found = session.plan_found

  def render? = @found.present?

  private
    attr_reader :found

    def block = found.block
    def shots = block.shots
end
