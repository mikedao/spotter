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
  # Deleting a session removes its pictures at once, not in a background job
  # that only runs if a job worker does.
  has_one_attached :before_image, dependent: :purge
  has_one_attached :after_image, dependent: :purge
  has_one_attached :closeup_before, dependent: :purge
  has_one_attached :closeup_after, dependent: :purge

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

  # --- in a match or final (Course): sighter or match shot, in time or not ---

  def sighter? = stage == "sighter"
  def penalized? = penalty.present?
  def stage_label = sighter? ? "sighter" : (match_number && "shot #{match_number}")

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

  # Delete a shot that wasn't one (a phantom, a double count): its pictures and
  # call go with it, and everything after it moves up a number - the card still
  # reads 1, 2, 3..., and in a match or final so do the competition shots, with a
  # match's 10-shot series recounted (a final's series are its timed windows, so
  # they stay). The engine matches its events by engine_shot_id, not number.
  def remove!
    transaction do
      destroy!
      card.shots.where("number > ?", number).update_all("number = number - 1") if number
      renumber_competition_shots_after(match_number) if match_number
    end
  end

  # The series a competition shot is in, counted from its number (a match: every
  # 10), or nil when series aren't counted by number (finals: timed windows).
  def self.series_for(session, match_number)
    size = session.course_info&.series_size
    size && ((match_number - 1) / size) + 1
  end

  def pinpointed? = pinpointed_at.present?

  # A capture the engine could not score, scored by the shooter: they tapped the
  # hole on its picture and the engine turned the tap into target mm
  # (ShotPinpoint). It becomes a scored shot in its place in firing order - the
  # shots after it on the card move down a number, and in a match or final it
  # joins the stage of the shot before it (sighter or match), renumbering the
  # competition shots after it. Marked pinpointed_at: placed by the shooter.
  def score_by_hand!(x_mm:, y_mm:, closeup:, closeups: {})
    raise ArgumentError, "already scored" if scored?

    session = practice_session
    score = session.target_spec.score_xy(x_mm, y_mm)
    transaction do
      number = (card.shots.where(status: "scored").where(fired_at: ...fired_at).maximum(:number) || 0) + 1
      card.shots.where(status: "scored").where(number: number..).update_all("number = number + 1")
      update!(status: "scored", number:, x_mm:, y_mm:, r_mm: Math.hypot(x_mm, y_mm), rule: "pellet",
              decimal_score: score.decimal, ring: score.ring, inner_ten: score.inner_ten,
              estimates: { "closeup" => closeup }, pinpointed_at: Time.current, **course_place(session))
      closeups.each { |name, jpeg| public_send(name).attach(io: StringIO.new(jpeg), filename: "#{name}.jpg", content_type: "image/jpeg") }
    end
    self
  end

  # Record the shooter's call. A tapped position, when given, is the most precise
  # label; the ring is still stored as said, since that is what the shooter judged.
  def record_call!(ring:, decimal: nil, x_mm: nil, y_mm: nil, note: nil)
    update!(call_ring: ring, call_decimal: decimal.presence, call_x_mm: x_mm.presence,
            call_y_mm: y_mm.presence, call_note: note.presence, called_at: Time.current)
  end

  private
    # In a match or final: the stage of the scored shot before it (or after it,
    # for the first), and if a competition shot, the next number - the ones after
    # it move up one, a match's series recounted.
    def course_place(session)
      return {} unless session.course

      scored = session.shots.where(status: "scored").where.not(id:).order(:fired_at)
      neighbour = scored.where(fired_at: ...fired_at).last || scored.where("fired_at > ?", fired_at).first
      stage = neighbour&.stage || "match"
      return { stage: } unless stage == "match"

      n = (scored.where(fired_at: ...fired_at).maximum(:match_number) || 0) + 1
      session.shots.where(match_number: n..).order(match_number: :desc).each do |shot|
        shot.update_columns(match_number: shot.match_number + 1, series: Shot.series_for(session, shot.match_number + 1) || shot.series)
      end
      { stage:, match_number: n, series: Shot.series_for(session, n) || neighbour&.series }
    end

    def renumber_competition_shots_after(gone)
      session = practice_session
      session.shots.where("match_number > ?", gone).order(:match_number).each do |shot|
        n = shot.match_number - 1
        shot.update_columns(match_number: n, series: Shot.series_for(session, n) || shot.series)
      end
    end
end
