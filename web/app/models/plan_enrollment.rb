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
  #
  # It can also hold rest days the shooter added ("rest-1", "rest-2"...): a day made
  # into a rest day pushes it and everything after it one day later, so the calendar
  # grows by a day for each. A rest day has no ticks or notes: it is only a gap.
  PAUSE = /\Arest-\d+\z/
  Pause = Data.define(:ref) do
    def pause? = true
    def rest? = true
    def range? = false
    def kind = "rest"
    def title = "Rest day"
    def week = nil
    def day = nil
  end

  def order
    saved = (JSON.parse(schedule) if schedule.present?) rescue nil
    valid = saved.is_a?(Array) && saved.grep(PAUSE).uniq.size == saved.grep(PAUSE).size && saved.grep_v(PAUSE).sort == natural_order.sort
    valid ? saved : natural_order
  end

  def natural_order = TrainingPlan.weeks.flat_map { |week| week.days.map(&:ref) }
  def moved? = order != natural_order

  # 1 on the start date; zero or less before it.
  def day_number(date = Time.zone.today) = (date - started_on).to_i + 1

  # [week, day] of the plan on a date, or nil before it starts and after it ends.
  def position(date = Time.zone.today)
    n = day_number(date)
    return unless n.between?(1, order.size)

    TrainingPlan.parse(order[n - 1])
  end

  def today = position&.then { |week, day| self.day(week, day) }

  # The plan's day as this shooter has it: a range day made a match is the match.
  def day(week, day) = TrainingPlan.day(week, day, match: match_day?("#{week}-#{day}"))
  def match_day?(ref) = Array(match_days).include?(ref.to_s)

  # "Make it a match" (the shooter, 2026-11-21): a week's range day becomes a full
  # 60-shot match, and back. Refused for a day that is not a range day, or once a
  # session has been shot for it (its block numbers would point elsewhere).
  def make_match!(ref) = set_match!(ref, true)
  def make_range!(ref) = set_match!(ref, false)

  # Is today a rest day the shooter added (the plan has started and is not over)?
  def rest_today? = day_number.between?(1, order.size) && order[day_number - 1].match?(PAUSE)
  def scheduled_on(week, day) = date_of("#{week}-#{day}")
  def date_of(ref) = started_on + order.index(ref)
  def starts_in = (started_on - Time.zone.today).to_i.clamp(0, nil)

  # The calendar as weeks of seven days, each a list of plan days (what was moved
  # shows under its new date).
  def calendar = order.each_slice(TrainingPlan::DAYS_PER_WEEK).map { |refs| refs.map { plan_day_for(it) } }

  # Calendar week (1-12) of today, for opening that week on the plan page.
  def calendar_week_now = day_number.clamp(1, order.size).then { (it - 1) / TrainingPlan::DAYS_PER_WEEK + 1 }

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
    save_order!(moved)
  end

  # The day becomes a rest day: it and every day after it move one day later.
  def add_rest!(ref)
    index = order.index(ref.to_s) or raise Refused, "That isn't a day of the plan."
    taken = order.grep(PAUSE).filter_map { it[/\d+/].to_i }
    moved = order.dup.insert(index, "rest-#{(taken.max || 0) + 1}")
    save_order!(moved)
  end

  # A rest day the shooter added goes: the days after it move one day earlier.
  def remove_rest!(ref)
    raise Refused, "That isn't an added rest day." unless ref.to_s.match?(PAUSE) && order.include?(ref.to_s)

    save_order!(order - [ ref.to_s ])
  end

  def reset_schedule! = update!(schedule: nil)

  def finished? = day_number > order.size

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

    found = TrainingPlan.find_block("#{week}-#{day}-#{block}", enrollment: self) or return
    transaction do
      practice_session.update!(plan_week: week, plan_day: day, plan_block: block)
      tags = found.block.session.tags.filter_map { find_or_create_exercise(it) }
      practice_session.update!(exercises: practice_session.exercises | tags) if tags.any?
    end
  end

  private
    def plan_day_for(ref) = ref.match?(PAUSE) ? Pause.new(ref) : day(*TrainingPlan.parse(ref))

    def set_match!(ref, on)
      ref = ref.to_s
      plan_day = TrainingPlan.parse(ref)&.then { TrainingPlan.day(*it) }
      raise Refused, "Only a range day can be made a match." unless plan_day&.range?
      return self if match_day?(ref) == on

      if user.practice_sessions.for_plan_day(plan_day.week, plan_day.day).exists?
        raise Refused, "A session has been shot for that day already, so it stays as it is."
      end

      update!(match_days: on ? (Array(match_days) | [ ref ]) : (Array(match_days) - [ ref ]))
      self
    end

    # Saves a new order unless a calendar week would get two range days (a Pardini day
    # at the range: the shooter has one a week).
    def save_order!(moved)
      crowded = moved.each_slice(TrainingPlan::DAYS_PER_WEEK).each_with_index.find do |refs, _|
        refs.count { plan_day_for(it).range? } > 1
      end
      raise Refused, "That would put two range days in week #{crowded[1] + 1}. Move one of them elsewhere first." if crowded

      update!(schedule: (moved == natural_order ? nil : moved.to_json))
      @workouts_by_day = nil
      self
    end

    def workouts_by_day = (@workouts_by_day ||= workouts.index_by { [ it.week, it.day ] })

    def find_or_create_exercise(name)
      user.exercises.where("lower(name) = ?", name.downcase).first || user.exercises.create(name:)&.then { it if it.persisted? }
    end

    def started_on_is_not_far_ahead
      errors.add(:started_on, "can't be more than a month away") if started_on && started_on > Time.zone.today + 30
    end
end
