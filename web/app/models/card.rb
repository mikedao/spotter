# One target card within a session. The engine announces a new card when it sees
# the card change (old holes gone); shots belong to the card that was up.
class Card < ApplicationRecord
  belongs_to :practice_session, inverse_of: :cards
  has_many :shots, -> { order(:fired_at) }, dependent: :destroy, inverse_of: :card

  validates :number, presence: true, uniqueness: { scope: :practice_session_id }

  def scored_shots = shots.select(&:scored?)
  def stats = CardStats.new(scored_shots, practice_session.target_spec)
  def next_shot_number = (shots.maximum(:number) || 0) + 1
end
