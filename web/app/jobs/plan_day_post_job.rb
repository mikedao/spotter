# Posts a training-plan day to CompetitiveShooter.org when it is ticked done
# (PlanWorkoutsController#update), off the request: drawing and uploading the
# pictures takes a few seconds. Once per day - a day posted before is left alone,
# so "Not done after all" and ticking it again makes no second post. A failure is
# kept on the workout (`share_error`) and shown on the day's page with "Post it".
class PlanDayPostJob < ApplicationJob
  queue_as :default

  def perform(workout)
    user = workout.plan_enrollment.user
    return unless workout.done? && user.cso_connected?

    share = PlanDayShare.new(user, workout.week, workout.day)
    return if share.posted.exists?

    share.post!
    workout.update!(share_error: nil)
  rescue CompetitiveShooter::Error, SharePicture::RenderError, PlanDayShare::Invalid => e
    workout.update!(share_error: e.message)
  end
end
