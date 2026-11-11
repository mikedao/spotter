# One shot, as the engine scored it (the PROPOSAL columns) and as the shooter
# called it on review (the CALL columns). The two are never merged in the table:
# their difference is the training label for the model meant to replace the
# hand-written rules. Everything shown as "the score" goes through the final_*
# methods, where the call wins.
#
# An engine capture that heard a shot but could not score it is kept too
# (status "unscored", with its frames), so nothing is silently lost.
class Shot < ApplicationRecord
  belongs_to :card, inverse_of: :shots
  has_one :practice_session, through: :card

  # Full frames from the engine, and the straightened close-ups (top-down,
  # CLOSEUP_PX_PER_MM, centred on CLOSEUP_CENTRE) the review screen draws on.
  has_one_attached :before_image
  has_one_attached :after_image
  has_one_attached :closeup_before
  has_one_attached :closeup_after

  STATUSES = %w[ scored unscored ].freeze
  TRIGGERS = %w[ sound camera final_check ].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :trigger, inclusion: { in: TRIGGERS }, allow_nil: true
  validates :call_ring, inclusion: { in: 0..10 }, allow_nil: true
  validates :call_decimal, numericality: { in: 0..10.9 }, allow_nil: true

  scope :needing_review, -> { where(status: "scored", called_at: nil).where("line_call OR ambiguous OR overlap") }

  def scored? = status == "scored"
  def unscored? = status == "unscored"
  def called? = called_at.present?
  def flagged? = line_call || ambiguous || overlap

  def flags
    [ ("line call" if line_call), ("ring uncertain" if ambiguous), ("overlaps a hole" if overlap) ].compact
  end

  # --- what to show: the shooter's call wins over the proposal ---

  def final_x_mm = call_x_mm || x_mm
  def final_y_mm = call_y_mm || y_mm

  def final_score
    return nil unless scored?

    @final_score ||= if call_x_mm && call_y_mm
      practice_session.target_spec.score_xy(call_x_mm, call_y_mm)
    end
  end

  def final_ring = call_ring || final_score&.ring || ring
  def final_decimal = call_decimal&.to_f || final_score&.decimal || decimal_score&.to_f
  def final_inner_ten? = final_score ? final_score.inner_ten : inner_ten

  def direction
    return nil unless scored? && final_x_mm && final_y_mm

    TargetSpec.direction(final_x_mm, final_y_mm, inner_ten: final_inner_ten?)
  end

  # Did the call change the ring the rules proposed? (The headline training signal.)
  def corrected? = called? && call_ring.present? && call_ring != ring

  # Record the shooter's call. A tapped position, when given, is the most precise
  # label; the ring is still stored as said, since that is what the shooter judged.
  def record_call!(ring:, decimal: nil, x_mm: nil, y_mm: nil, note: nil)
    update!(call_ring: ring, call_decimal: decimal.presence, call_x_mm: x_mm.presence,
            call_y_mm: y_mm.presence, call_note: note.presence, called_at: Time.current)
  end
end
