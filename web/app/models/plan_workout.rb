# What a user did on one day of the training plan: a note, and whether they
# finished. Made the first time there is something to remember about the day.
# (The sessions shot for a day are on the sessions: PracticeSession#plan_week.)
class PlanWorkout < ApplicationRecord
  belongs_to :plan_enrollment

  validates :week, inclusion: { in: 1..TrainingPlan::WEEKS }
  validates :day, inclusion: { in: 1..TrainingPlan::DAYS_PER_WEEK }
  validates :day, uniqueness: { scope: %i[ plan_enrollment_id week ] }
  validates :note, length: { maximum: 4000 }

  def done? = completed_at.present?
  def plan_day = TrainingPlan.day(week, day)

  def complete!(note: self.note) = update!(completed_at: completed_at || Time.current, note: note.to_s.strip.presence)
  def reopen!(note: self.note) = update!(completed_at: nil, note: note.to_s.strip.presence)
end
