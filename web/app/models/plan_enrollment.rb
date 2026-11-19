# A user following the training plan: the day they started it. Which day of the
# plan it is today follows from that (a week is seven days, rest days included),
# so a missed day just stays undone and can be caught up from the plan page.
class PlanEnrollment < ApplicationRecord
  belongs_to :user
  has_many :workouts, class_name: "PlanWorkout", dependent: :destroy

  validates :started_on, presence: true
  validate :started_on_is_not_far_ahead

  # 1 on the start date; zero or less before it.
  def day_number(date = Time.zone.today) = (date - started_on).to_i + 1

  # [week, day] of the plan on a date, or nil before it starts and after it ends.
  def position(date = Time.zone.today)
    n = day_number(date)
    return unless n.between?(1, TrainingPlan.total_days)

    [ (n - 1) / TrainingPlan::DAYS_PER_WEEK + 1, (n - 1) % TrainingPlan::DAYS_PER_WEEK + 1 ]
  end

  def today = position&.then { |week, day| TrainingPlan.day(week, day) }
  def scheduled_on(week, day) = started_on + ((week - 1) * TrainingPlan::DAYS_PER_WEEK + day - 1)
  def starts_in = (started_on - Time.zone.today).to_i.clamp(0, nil)
  def finished? = day_number > TrainingPlan.total_days

  def workout_for(week, day) = workouts_by_day[[ week, day ]]
  def done?(week, day) = workout_for(week, day)&.done? || false

  # Workout days (not rest days) finished so far, and how many the plan has.
  def done_count = TrainingPlan.workout_days.count { done?(it.week, it.day) }
  def workout_count = TrainingPlan.workout_days.size

  # Workout days before today that were not finished.
  def missed
    TrainingPlan.workout_days.select { scheduled_on(it.week, it.day) < Time.zone.today && !done?(it.week, it.day) }
  end

  # A session started for one shooting block of the plan: remembered on the session
  # (plan_week / plan_day / plan_block), and tagged with the block's exercises (found or
  # made, by name) so the journal can filter on them.
  def link_session!(practice_session, week:, day:, block:)
    raise ArgumentError, "not this user's session" unless practice_session.user_id == user_id

    found = TrainingPlan.find_block("#{week}-#{day}-#{block}") or return
    transaction do
      practice_session.update!(plan_week: week, plan_day: day, plan_block: block)
      tags = found.block.session.tags.filter_map { find_or_create_exercise(it) }
      practice_session.update!(exercises: practice_session.exercises | tags) if tags.any?
    end
  end

  private
    def workouts_by_day = (@workouts_by_day ||= workouts.index_by { [ it.week, it.day ] })

    def find_or_create_exercise(name)
      user.exercises.where("lower(name) = ?", name.downcase).first || user.exercises.create(name:)&.then { it if it.persisted? }
    end

    def started_on_is_not_far_ahead
      errors.add(:started_on, "can't be more than a month away") if started_on && started_on > Time.zone.today + 30
    end
end
