# A user following the training plan: the day they started it. Which day of the
# plan it is today follows from that (a week is seven days, rest days included),
# so a missed day just stays undone and can be caught up from the plan page.
class PlanEnrollment < ApplicationRecord
  belongs_to :user
  has_many :workouts, class_name: "PlanWorkout", dependent: :destroy

  validates :started_on, presence: true
  validate :started_on_is_not_far_ahead

  # The plan's days in calendar order, as "week-day" references: as written until the
  # shooter swaps some (the saved `schedule`). A day keeps everything that is about it
  # (ticks, notes, sessions) when it moves, since those hang on its reference.
  def order
    saved = (JSON.parse(schedule) if schedule.present?) rescue nil
    saved.is_a?(Array) && saved.sort == natural_order.sort ? saved : natural_order
  end

  def natural_order = TrainingPlan.weeks.flat_map { |week| week.days.map(&:ref) }
  def moved? = order != natural_order

  # 1 on the start date; zero or less before it.
  def day_number(date = Time.zone.today) = (date - started_on).to_i + 1

  # [week, day] of the plan on a date, or nil before it starts and after it ends.
  def position(date = Time.zone.today)
    n = day_number(date)
    return unless n.between?(1, TrainingPlan.total_days)

    TrainingPlan.parse(order[n - 1])
  end

  def today = position&.then { |week, day| TrainingPlan.day(week, day) }
  def scheduled_on(week, day) = started_on + order.index("#{week}-#{day}")
  def starts_in = (started_on - Time.zone.today).to_i.clamp(0, nil)

  # The calendar as weeks of seven days, each a list of plan days (what was moved
  # shows under its new date).
  def calendar = order.each_slice(TrainingPlan::DAYS_PER_WEEK).map { |refs| refs.map { |ref| TrainingPlan.day(*TrainingPlan.parse(ref)) } }

  # Calendar week (1-12) of today, for opening that week on the plan page.
  def calendar_week_now = day_number.clamp(1, TrainingPlan.total_days).then { (it - 1) / TrainingPlan::DAYS_PER_WEEK + 1 }

  class Refused < StandardError; end

  # Two days trade places on the calendar. Refused when it would leave a calendar week
  # with two range days (a Pardini day at the range: the shooter has one a week) or
  # when either is not a day of the plan.
  def swap!(from, to)
    a, b = [ from, to ].map { order.index(it.to_s) }
    raise Refused, "That isn't a day of the plan." unless a && b
    return self if a == b

    moved = order.dup
    moved[a], moved[b] = moved[b], moved[a]
    crowded = moved.each_slice(TrainingPlan::DAYS_PER_WEEK).each_with_index.find do |refs, _|
      refs.count { TrainingPlan.day(*TrainingPlan.parse(it)).range? } > 1
    end
    raise Refused, "That would put two range days in week #{crowded[1] + 1}. Move one of them elsewhere first." if crowded

    update!(schedule: (moved == natural_order ? nil : moved.to_json))
    @workouts_by_day = nil
    self
  end

  def reset_schedule! = update!(schedule: nil)

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
