# One target card within a session. The engine announces a new card when it sees
# the card change (old holes gone); shots belong to the card that was up.
class Card < ApplicationRecord
  belongs_to :practice_session, inverse_of: :cards
  has_many :shots, -> { order(:fired_at) }, dependent: :destroy, inverse_of: :card

  validates :number, presence: true, uniqueness: { scope: :practice_session_id }

  def scored_shots = shots.select(&:scored?)
  def stats = CardStats.new(scored_shots, practice_session.target_spec, whole_rings: practice_session.whole_rings?)
  def next_shot_number = (shots.maximum(:number) || 0) + 1

  # The card the engine is scoring onto right now: new shots go on the session's
  # LATEST card, so while the session runs this one can't be deleted (its shots
  # would land on the card before it). Change cards first; then it is an earlier
  # card.
  def on_target? = practice_session.live? && practice_session.current_card == self

  # Delete a whole card (2026-11-13, the shooter: mid-session too): its shots,
  # calls and pictures go, and everything after it renumbers, as deleting a shot
  # does - later cards move up a number, and in a match or final the competition
  # shots are counted again from 1, a match's series with them (a final's series
  # are timed windows and stay). As with a deleted shot, a live engine still
  # counted these shots, so its spoken competition number runs ahead.
  def remove!
    raise ArgumentError, "the card on the target can't be deleted while the session runs" if on_target?

    session = practice_session
    transaction do
      destroy!
      session.cards.where("number > ?", number).order(:number).each { it.update_columns(number: it.number - 1) }
      session.shots.where.not(match_number: nil).order(:match_number).each.with_index(1) do |shot, n|
        next if shot.match_number == n

        shot.update_columns(match_number: n, series: Shot.series_for(session, n) || shot.series)
      end
    end
  end
end
