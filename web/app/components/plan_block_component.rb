# What the training plan set for this session: the block it was started for (Slow
# groups, Called shots...), its instructions always in view on the session page -
# a reminder while you shoot - and its cards, groups and tags one tap below. Static:
# the live panels beside it keep the count.
class PlanBlockComponent < ApplicationComponent
  def initialize(session:) = (@session, @found = session, session.plan_found)

  def render? = @found.present?

  private
    attr_reader :found

    def block = found.block
    def shots = block.shots
    def group_of = @session.group_of   # as chosen at Start, which may differ from the block
end
