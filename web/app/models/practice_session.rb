# One run of the engine's hands-free scorer (`phase1.py shot --auto`). Created by
# the first event the engine sends; cards and shots arrive live after that.
class PracticeSession < ApplicationRecord
  belongs_to :user
  belongs_to :gun, optional: true        # what was shot: optional, pre-selected (GearChoice)
  belongs_to :pellet, optional: true
  has_many :session_exercises, dependent: :destroy   # the diary's exercise tags
  has_many :exercises, through: :session_exercises
  has_secure_token :run_token   # the engine's events must present it (Api::EventsController)
  has_many :cards, -> { order(:number) }, dependent: :destroy, inverse_of: :practice_session
  has_many :shots, through: :cards

  # What the range screen's status line says; set from the engine's events.
  # "stopping" = Stop was pressed; the engine makes its final check, then ends.
  # "paused" = "Pause scoring" (changing cards: nothing is scored); "resuming" =
  # Resume pressed, the engine is finding the card again.
  STATUSES = %w[ starting ready card_off new_card shooting paused resuming stopping ended ].freeze

  validates :engine_session_id, presence: true, uniqueness: true
  validates :target, inclusion: { in: TargetSpec::SPECS.keys }
  validates :status, inclusion: { in: STATUSES }
  validates :course, inclusion: { in: Course::ALL.keys }, allow_nil: true
  validates :group_of, inclusion: { in: [ 0, 5, 10 ] }, allow_nil: true   # 0 = one group per card
  validates :gun_adjustments, :problems, :fixes, :learned, length: { maximum: 4000 }
  validate :gear_is_the_users_own
  validate :plan_block_is_in_the_plan

  scope :newest_first, -> { order(started_at: :desc) }
  scope :for_plan_day, ->(week, day) { where(plan_week: week, plan_day: day) }

  # Deleting a session takes its cards, shots, their pictures and the engine's
  # log with it. Never while its engine runs: stop it first.
  before_destroy :refuse_while_live, prepend: true   # before the cards go
  after_destroy_commit :remove_engine_log

  def target_spec = TargetSpec.fetch(target)
  def live? = ended_at.nil?

  # Continue: a finished PRACTICE session from today can be picked up again -
  # stop, improve something, carry on in one session (the shooter, 2026-11-12).
  # Not a match or final: their clock, sighting and series can't resume.
  def continuable? = !live? && course.blank? && started_at.in_time_zone.to_date == Time.zone.today

  # Time actually shooting: start to end, less the breaks a Continue bridged.
  def shooting_seconds = ((ended_at || Time.current) - started_at - break_seconds.to_i).clamp(0, nil)
  def current_card = cards.last

  # The card the next shot belongs to: the latest, or a first one.
  def card_for_new_shot(at:)
    current_card || cards.create!(number: 1, started_at: at)
  end

  def start_new_card!(at:)
    cards.create!(number: (cards.maximum(:number) || 0) + 1, started_at: at)
  end

  # A status from the engine - except that once Stop is pressed the screen keeps
  # saying so (a shot found by the final check must not read "ready") until the
  # engine's session_ended.
  def show_status!(value)
    update!(status: value) unless status == "stopping"
  end

  def course_info = Course.for(self)
  # How this session is scored, so totals and averages say what the rules count:
  # whole rings for pistol (qualification), decimals for rifle and finals.
  def whole_rings? = course_info ? course_info.whole_rings?(target) : target == "pistol"
  def gear_label = [ gun&.name, pellet&.label ].compact.join(" · ").presence   # "LP10 · RWS R10 Match · 4.49 mm"

  # The training plan block this session was started for (TrainingPlan::Found), if any: what the
  # shooter set out to do in it. Nil for a day started as a whole (before blocks had sessions).
  def plan_found = plan_block && TrainingPlan.find_block(plan_ref)
  # Shots per group when the plan block measures a card in runs (10 shots, two 5-shot groups).
  # Shot as the plan block asked: at least its shot count, sighters not counted.
  def completes_plan_block?
    shots = plan_found&.block&.shots
    shots.present? && cards.sum { |card| card.scored_shots.count { !it.sighter? } } >= shots
  end

  # Shots per group when the card is measured in runs (5-shot groups without
  # changing the card), or nil for one group per card. Chosen at Start (column;
  # 0 = whole card on purpose); older sessions from a plan block take the block's.
  def group_of
    chosen = self[:group_of]
    return chosen if chosen&.positive?
    return nil if chosen&.zero?

    plan_found&.block&.session&.group
  end
  # A plan block shot as a match simulation (the baseline, the half and full
  # matches: tagged "Match simulation" in training_plan.yml) - the only plan
  # sessions the journal's numbers count.
  MATCH_SIMULATION = "Match simulation"
  def plan_match_simulation? = plan_found&.block&.session&.tags.to_a.include?(MATCH_SIMULATION)

  def plan_ref = ([ plan_week, plan_day, plan_block ].compact.join("-") if plan_week)

  def title = [ course_info&.name, target_spec.name, started_at.strftime("%b %-d, %H:%M") ].compact.join(" · ")

  private
    def gear_is_the_users_own
      errors.add(:gun, "isn't one of yours") if gun && gun.user_id != user_id
      errors.add(:pellet, "isn't one of yours") if pellet && pellet.user_id != user_id
      errors.add(:gun, "is #{gun.kind_name.downcase.sub('air ', 'an air ')}, not for this target") if gun && gun.kind != target
    end

    def plan_block_is_in_the_plan
      return if plan_week.nil? && plan_day.nil? && plan_block.nil?

      ok = plan_week && plan_day && TrainingPlan.day(plan_week, plan_day) && (plan_block.nil? || plan_found)
      errors.add(:base, "That isn't a day of the training plan") unless ok
    end

    def refuse_while_live
      return unless live?

      errors.add(:base, "Stop the session before deleting it")
      throw :abort
    end

    def remove_engine_log
      path = engine_log.presence && Pathname(engine_log)
      path.delete if path&.file? && path.dirname == Rails.root.join("log", "engine")
    end
end
