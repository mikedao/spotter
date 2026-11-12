# One run of the engine's hands-free scorer (`phase1.py shot --auto`). Created by
# the first event the engine sends; cards and shots arrive live after that.
class PracticeSession < ApplicationRecord
  belongs_to :user
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
  def title = [ course_info&.name, target_spec.name, started_at.strftime("%b %-d, %H:%M") ].compact.join(" · ")

  private
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
