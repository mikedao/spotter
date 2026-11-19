# Today's day of the training plan: what it is and the way in. Shown on the plan
# page and at the top of Practice, so the day's work is one tap away. Says so
# when the plan has not started yet, or is over.
class PlanTodayComponent < ApplicationComponent
  def initialize(enrollment:) = @enrollment = enrollment

  private
    attr_reader :enrollment

    def day = enrollment.today
    def done? = day && enrollment.done?(day.week, day.day)
end
