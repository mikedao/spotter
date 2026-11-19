# One run of the hold drill: raise the gun, settle, hold for hold_seconds, lower,
# rest, repeat. The page's timer keeps the clock; this is what it reports at the
# end - holds completed, holds let down early, and the seconds actually held.
# Pardini unloaded or the air pistol uncocked: nothing here fires anything.
class HoldDrill < ApplicationRecord
  DEFAULTS = { reps: 10, hold_seconds: 8, rest_seconds: 20 }.freeze
  SETTLE_SECONDS = 3   # raise and settle before each hold starts
  # What the timer says in the shooter's Kokoro voice. Mirrors engine/voicelines.py's
  # HOLD_DRILL (a spec checks), so every voice has them rendered ahead (voices:export).
  CUES = %w[ raise hold lower rest three two one done ].freeze
  LIMITS = { reps: 1..30, hold_seconds: 3..60, rest_seconds: 5..120 }.freeze

  belongs_to :user

  validates :reps, inclusion: { in: LIMITS[:reps] }
  validates :hold_seconds, inclusion: { in: LIMITS[:hold_seconds] }
  validates :rest_seconds, inclusion: { in: LIMITS[:rest_seconds] }
  validates :reps_done, :let_downs, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :held_seconds, numericality: { greater_than_or_equal_to: 0 }
  validates :performed_at, presence: true
  validate :holds_fit_the_drill
  validate :plan_day_is_a_whole_day

  scope :newest_first, -> { order(performed_at: :desc, id: :desc) }
  scope :since, ->(days) { days ? where(performed_at: days.to_i.days.ago..) : all }

  # The settings for a new drill from a page's params: each clamped into its limits.
  def self.settings(params)
    DEFAULTS.to_h { |key, default| [ key, params[key].to_s.match?(/\A\d+\z/) ? params[key].to_i.clamp(LIMITS[key]) : default ] }
  end

  def holds = reps_done + let_downs
  def finished? = holds >= reps
  def completion = holds.zero? ? 0 : (100.0 * reps_done / holds).round   # of the holds attempted, how many were held
  # Does this run do a plan block's hold drill (a TrainingPlan::HoldSpec)? Every hold of
  # it attempted, at the block's length or longer. Holds let down still count: the
  # Journal's steadiness figure is where those show.
  def completes?(spec) = finished? && reps >= spec.reps && hold_seconds >= spec.hold

  def plan_ref = ("#{plan_week}-#{plan_day}" if plan_week)

  def summary
    "#{reps_done} of #{reps} holds of #{hold_seconds} s" + (let_downs.positive? ? ", #{let_downs} let down" : "")
  end

  private
    def holds_fit_the_drill
      errors.add(:base, "No holds to save") if holds.zero?
      errors.add(:reps_done, "can't be more holds than the drill has") if holds > reps
      errors.add(:held_seconds, "is more than the drill allows") if held_seconds > reps * hold_seconds + 1
    end

    def plan_day_is_a_whole_day
      return if plan_week.nil? && plan_day.nil?

      errors.add(:plan_day, "isn't a day of the plan") unless plan_week && plan_day && TrainingPlan.day(plan_week, plan_day)
    end
end
