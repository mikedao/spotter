# One run of the timed-fire timer (Pardini dry fire): from low ready, on a beep,
# `shots` shots in `string_seconds`, then a rest, for `strings` strings. The page
# keeps the clock; this is what it reports: how many strings ran to the stop beep.
# Nothing here fires anything: it is dry fire, magazine out.
class TimedDrill < ApplicationRecord
  DEFAULTS = { strings: 4, string_seconds: 20, shots: 5, rest_seconds: 30 }.freeze
  LIMITS = { strings: 1..16, string_seconds: 5..60, shots: 1..10, rest_seconds: 10..120 }.freeze
  READY_SECONDS = (4..7)   # the wait from "ready" to the start beep is random in this range
  LEAD_IN_SECONDS = 10     # after Start, time to put the phone down and get into position
  # Spoken in the shooter's voice; every one is already rendered for every voice
  # (hold drills and the range officer use them): ready, stop, rest, three, two, one, done.
  CUES = %w[ ready stop rest three two one done ].freeze

  belongs_to :user

  validates :strings, inclusion: { in: LIMITS[:strings] }
  validates :string_seconds, inclusion: { in: LIMITS[:string_seconds] }
  validates :shots, inclusion: { in: LIMITS[:shots] }
  validates :rest_seconds, inclusion: { in: LIMITS[:rest_seconds] }
  validates :strings_done, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :performed_at, presence: true
  validate :strings_fit_the_drill
  validate :plan_day_is_a_whole_day

  scope :newest_first, -> { order(performed_at: :desc, id: :desc) }
  scope :since, ->(days) { days ? where(performed_at: days.to_i.days.ago..) : all }

  def self.settings(params)
    DEFAULTS.to_h { |key, default| [ key, params[key].to_s.match?(/\A\d+\z/) ? params[key].to_i.clamp(LIMITS[key]) : default ] }
  end

  def finished? = strings_done >= strings

  # Does this run do a plan block's timed drill (a TrainingPlan::TimedSpec)? Every
  # string shot, at least as many, in the block's time or less.
  def completes?(spec) = finished? && strings >= spec.strings && string_seconds <= spec.seconds

  def plan_ref = ("#{plan_week}-#{plan_day}" if plan_week)

  def summary = "#{strings_done} of #{strings} strings of #{shots} in #{string_seconds} s"

  private
    def strings_fit_the_drill
      errors.add(:base, "No strings to save") if strings_done.zero?
      errors.add(:strings_done, "can't be more strings than the drill has") if strings_done > strings
    end

    def plan_day_is_a_whole_day
      return if plan_week.nil? && plan_day.nil?

      errors.add(:plan_day, "isn't a day of the plan") unless plan_week && plan_day && TrainingPlan.day(plan_week, plan_day)
    end
end
