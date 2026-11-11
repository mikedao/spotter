# The heart of the range screen: the current card's target, its latest shot large,
# the card's numbers, and every shot on it. Replaced whole on each engine event
# (LiveBroadcast), so it is always rendered from the database, never patched.
class LivePanelComponent < ApplicationComponent
  def initialize(session:)
    @session = session
    @card = session.current_card
  end

  def shots = @card ? @card.shots.to_a : []
  def scored = shots.select(&:scored?)
  def latest = scored.last
  def stats = CardStats.new(scored, @session.target_spec)
  def spec = @session.target_spec
  def earlier_cards = @session.cards.to_a - [ @card ]
end
