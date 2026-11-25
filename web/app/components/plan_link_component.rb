# A finished session that is NOT linked to the training plan, shot on a plan day:
# offers that day's shooting blocks, so a session that should have counted can be
# counted after the fact (the safety net for a Start step that lost its plan block).
# Only blocks of the same kind (practice / match / final) as the session.
class PlanLinkComponent < ApplicationComponent
  def initialize(session:) = @session = session

  def render? = !@session.live? && @session.plan_week.nil? && blocks.any?

  private
    def day
      @day ||= enrollment&.position(@session.started_at.to_date)&.then { |week, day| enrollment.day(week, day) }
    end

    def enrollment = @session.user.plan_enrollment

    def blocks
      @blocks ||= day ? day.blocks.select { it.session && it.session.course.to_s == @session.course.to_s } : []
    end
end
