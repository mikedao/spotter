# Moving the plan's days around the calendar (drag a day onto another, or tap two):
# they trade places, as long as no week ends up with two range days.
class PlanSchedulesController < ApplicationController
  before_action :set_enrollment

  def swap
    @enrollment.swap!(params[:from], params[:to])
    back notice: "Swapped."
  rescue PlanEnrollment::Refused => e
    back alert: e.message
  end

  # The day becomes a rest day and the plan shifts a day later.
  def add_rest
    @enrollment.add_rest!(params[:ref])
    back notice: "Rest day added. The days from there moved a day later."
  rescue PlanEnrollment::Refused => e
    back alert: e.message
  end

  def remove_rest
    @enrollment.remove_rest!(params[:ref])
    back notice: "Rest day taken out. The days after it moved a day earlier."
  rescue PlanEnrollment::Refused => e
    back alert: e.message
  end

  # Back to the order the plan was written in.
  def reset
    @enrollment.reset_schedule!
    redirect_to training_plan_path, notice: "Days back in the order the plan was written.", status: :see_other
  end

  private
    def set_enrollment = (@enrollment = Current.user.plan_enrollment) || redirect_to(training_plan_path)

    # Keep the calendar week the shooter was looking at open.
    def back(flash)
      redirect_to training_plan_path(open: params[:open].presence), **flash, status: :see_other
    end
end
