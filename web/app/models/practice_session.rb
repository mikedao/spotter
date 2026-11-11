# One run of the engine's hands-free scorer (`phase1.py shot --auto`). Created by
# the first event the engine sends; cards and shots arrive live after that.
class PracticeSession < ApplicationRecord
  belongs_to :user
  has_secure_token :run_token   # the engine's events must present it (Api::EventsController)
  has_many :cards, -> { order(:number) }, dependent: :destroy, inverse_of: :practice_session
  has_many :shots, through: :cards

  # What the range screen's status line says; set from the engine's events.
  STATUSES = %w[ starting ready card_off new_card shooting ended ].freeze

  validates :engine_session_id, presence: true, uniqueness: true
  validates :target, inclusion: { in: TargetSpec::SPECS.keys }
  validates :status, inclusion: { in: STATUSES }

  scope :newest_first, -> { order(started_at: :desc) }

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

  def title = "#{target_spec.name} · #{started_at.strftime('%b %-d, %H:%M')}"
end
