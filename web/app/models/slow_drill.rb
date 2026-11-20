# One run of the slow dry fire timer (Pardini): raise and settle, then up to
# `limit_seconds` to break the shot, tapping when it does. A shot not broken in time,
# or let down, does not count and is taken again; the run goes on until `shots` are
# fired. Rests between shots and between strings of `string_size`. Dry fire only.
class SlowDrill < ApplicationRecord
  DEFAULTS = { shots: 10, string_size: 10, limit_seconds: 12, between_seconds: 10, string_rest_seconds: 60 }.freeze
  LIMITS = { shots: 1..60, string_size: 1..20, limit_seconds: 5..30, between_seconds: 3..60, string_rest_seconds: 10..180 }.freeze
  SETTLE_SECONDS = 3
  # Spoken in the picked voice; all already exported (the hold drill's cues).
  CUES = %w[ raise hold lower rest three two one done ].freeze

  belongs_to :user

  validates :shots, inclusion: { in: LIMITS[:shots] }
  validates :string_size, inclusion: { in: LIMITS[:string_size] }
  validates :limit_seconds, inclusion: { in: LIMITS[:limit_seconds] }
  validates :between_seconds, inclusion: { in: LIMITS[:between_seconds] }
  validates :string_rest_seconds, inclusion: { in: LIMITS[:string_rest_seconds] }
  validates :shots_fired, :let_downs, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :break_seconds, numericality: { greater_than_or_equal_to: 0 }
  validates :performed_at, presence: true
  validate :fits_the_drill
  validate :plan_day_is_a_whole_day

  scope :newest_first, -> { order(performed_at: :desc, id: :desc) }
  scope :since, ->(days) { days ? where(performed_at: days.to_i.days.ago..) : all }

  def self.settings(params)
    DEFAULTS.to_h { |key, default| [ key, params[key].to_s.match?(/\A\d+\z/) ? params[key].to_i.clamp(LIMITS[key]) : default ] }
  end

  def finished? = shots_fired >= shots
  def attempts = shots_fired + let_downs
  def first_time_rate = attempts.zero? ? nil : (100.0 * shots_fired / attempts).round   # shots fired of all raises
  def mean_break_seconds = shots_fired.zero? ? nil : (break_seconds / shots_fired).round(1)

  # Does this run do a plan block's slow dry fire (`shots` fired, in the block's limit or less)?
  def completes?(block_shots, block_limit) = shots_fired >= block_shots && limit_seconds <= block_limit

  def plan_ref = ("#{plan_week}-#{plan_day}" if plan_week)

  def summary
    "#{shots_fired} of #{shots} slow shots in #{limit_seconds} s" + (let_downs.positive? ? ", #{let_downs} let down" : "")
  end

  private
    def fits_the_drill
      errors.add(:base, "No shots to save") if shots_fired.zero? && let_downs.zero?
      errors.add(:shots_fired, "can't be more shots than the drill has") if shots_fired > shots
      errors.add(:break_seconds, "is more than the drill allows") if break_seconds > shots_fired * limit_seconds + 1
    end

    def plan_day_is_a_whole_day
      return if plan_week.nil? && plan_day.nil?

      errors.add(:plan_day, "isn't a day of the plan") unless plan_week && plan_day && TrainingPlan.day(plan_week, plan_day)
    end
end
