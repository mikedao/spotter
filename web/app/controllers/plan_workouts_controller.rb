# One day of the training plan: what to do, a note, ticking it off, and the way
# into a Spotter session for it (the day's tags go on that session).
class PlanWorkoutsController < ApplicationController
  before_action :set_day

  def show
    @workout = @enrollment.workout_for(@day.week, @day.day)
    @sessions = Current.user.practice_sessions.for_plan_day(@day.week, @day.day).newest_first.includes(cards: :shots)
    @drills = Current.user.hold_drills.where(plan_week: @day.week, plan_day: @day.day).newest_first
    @slow_drills = Current.user.slow_drills.where(plan_week: @day.week, plan_day: @day.day).newest_first
    @timed_drills = Current.user.timed_drills.where(plan_week: @day.week, plan_day: @day.day).newest_first
    @running = EngineRunner.running
  end

  def update
    workout = @enrollment.workouts.find_or_initialize_by(week: @day.week, day: @day.day)
    params[:done] == "0" ? workout.reopen!(note: params[:note]) : workout.complete!(note: params[:note])
    # Back to the day, never on to the post composer: posting is an option the finished
    # day offers (the shooter, 2026-11-24), not a step after ticking it.
    redirect_to plan_workout_path(@day.week, @day.day), notice: workout.done? ? "Done. Nice work." : "Marked as not done.", status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_to plan_workout_path(@day.week, @day.day), alert: "#{e.record.errors.full_messages.to_sentence}.", status: :see_other
  end

  private
    def set_day
      @enrollment = Current.user.plan_enrollment or return redirect_to(training_plan_path)
      @day = @enrollment.day(params[:week].to_i, params[:day].to_i) or raise ActionController::RoutingError, "Not Found"
    end
end
