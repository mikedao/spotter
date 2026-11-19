# What a user did on one day of the training plan: the air pistol session they
# started for it, a note, and whether they finished. Made the first time there
# is something to remember about the day.
class PlanWorkout < ApplicationRecord
  belongs_to :plan_enrollment
  belongs_to :practice_session, optional: true

  validates :week, inclusion: { in: 1..TrainingPlan::WEEKS }
  validates :day, inclusion: { in: 1..TrainingPlan::DAYS_PER_WEEK }
  validates :day, uniqueness: { scope: %i[ plan_enrollment_id week ] }
  validates :note, length: { maximum: 4000 }
  validate :session_is_the_users_own

  def done? = completed_at.present?
  def plan_day = TrainingPlan.day(week, day)

  def complete!(note: self.note) = update!(completed_at: completed_at || Time.current, note: note.to_s.strip.presence)
  def reopen!(note: self.note) = update!(completed_at: nil, note: note.to_s.strip.presence)

  private
    def session_is_the_users_own
      errors.add(:practice_session, "isn't one of yours") if practice_session && practice_session.user_id != plan_enrollment.user_id
    end
end
