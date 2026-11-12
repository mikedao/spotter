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
  STATUSES = %w[ starting ready card_off new_card shooting stopping ended ].freeze

  validates :engine_session_id, presence: true, uniqueness: true
  validates :target, inclusion: { in: TargetSpec::SPECS.keys }
  validates :status, inclusion: { in: STATUSES }
  validates :course, inclusion: { in: Course::ALL.keys }, allow_nil: true
  validates :gun_adjustments, :problems, :fixes, :learned, length: { maximum: 4000 }
  validate :gear_is_the_users_own

  scope :newest_first, -> { order(started_at: :desc) }

  # Deleting a session takes its cards, shots, their pictures and the engine's
  # log with it. Never while its engine runs: stop it first.
  before_destroy :refuse_while_live, prepend: true   # before the cards go
  after_destroy_commit :remove_engine_log

  def target_spec = TargetSpec.fetch(target)
  def live? = ended_at.nil?
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
  def gear_label = [ gun&.name, pellet&.label ].compact.join(" · ").presence   # "LP10 · RWS R10 Match · 4.49 mm"

  def title = [ course_info&.name, target_spec.name, started_at.strftime("%b %-d, %H:%M") ].compact.join(" · ")

  private
    def gear_is_the_users_own
      errors.add(:gun, "isn't one of yours") if gun && gun.user_id != user_id
      errors.add(:pellet, "isn't one of yours") if pellet && pellet.user_id != user_id
      errors.add(:gun, "is #{gun.kind_name.downcase.sub('air ', 'an air ')}, not for this target") if gun && gun.kind != target
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
