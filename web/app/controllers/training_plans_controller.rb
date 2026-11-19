# The training plan (TrainingPlan): its overview, starting it, and leaving it.
class TrainingPlansController < ApplicationController
  def show
    @enrollment = Current.user.plan_enrollment
    @running = EngineRunner.running
  end

  # Start the plan on a date (today unless the shooter picks another).
  def create
    return redirect_to(training_plan_path) if Current.user.plan_enrollment

    Current.user.create_plan_enrollment!(started_on: start_date)
    redirect_to training_plan_path, notice: "Plan started.", status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_to training_plan_path, alert: "#{e.record.errors.full_messages.to_sentence}.", status: :see_other
  end

  # Leave the plan: the days ticked off go with it. Sessions stay.
  def destroy
    Current.user.plan_enrollment&.destroy
    redirect_to training_plan_path, notice: "Left the plan.", status: :see_other
  end

  private
    def start_date = (Date.iso8601(params[:started_on].to_s) rescue Time.zone.today)
end
