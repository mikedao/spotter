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
    was_done = workout.done?
    params[:done] == "0" ? workout.reopen!(note: params[:note]) : workout.complete!(note: params[:note])
    posting = !was_done && workout.done? && post_day?(workout)
    if posting
      workout.update!(share_error: nil)
      PlanDayPostJob.perform_later(workout)
    end
    notice = if posting then "Done. Nice work. Posting it to CompetitiveShooter.org."
    elsif workout.done? then "Done. Nice work."
    else "Marked as not done."
    end
    redirect_to plan_workout_path(@day.week, @day.day), notice:, status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_to plan_workout_path(@day.week, @day.day), alert: "#{e.record.errors.full_messages.to_sentence}.", status: :see_other
  end

  private
    # Ticking a workout day done posts it to CompetitiveShooter.org (the shooter's
    # call, 2026-11-20), once, when there is a key to post with.
    def post_day?(workout)
      !@day.rest? && Current.user.cso_connected? &&
        !Current.user.shared_posts.exists?(plan_week: workout.week, plan_day: workout.day)
    end

    def set_day
      @enrollment = Current.user.plan_enrollment or return redirect_to(training_plan_path)
      @day = TrainingPlan.day(params[:week].to_i, params[:day].to_i) or raise ActionController::RoutingError, "Not Found"
    end
end
