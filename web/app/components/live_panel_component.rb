# The range screen's live parts: the current card's target, its latest shot large,
# the card's numbers, and every shot on it. Each section is its own element,
# replaced whole on each engine event (LiveBroadcast) and always rendered from
# the database - separately, so the live camera picture between them is left alone.
#
#   LivePanelComponent.new(session:, section: :target)   # :target :latest :stats :list
class LivePanelComponent < ApplicationComponent
  SECTIONS = %i[ target latest stats list ].freeze

  # The target fills the window's height (less the session header), so the whole
  # card is always in view without scrolling - and beside the taller right column
  # (camera, numbers, shot list) it sticks, so scrolling the list keeps it in view.
  TARGET_SIZE = "mx-auto w-full max-w-[calc(100svh_-_7.5rem)] min-w-72 lg:w-[min(calc(100svh_-_7.5rem),60rem)] " \
                "lg:sticky lg:top-4".freeze

  def initialize(session:, section:)
    raise ArgumentError, "unknown section #{section}" unless SECTIONS.include?(section)

    @session = session
    @section = section
    @card = session.current_card
  end

  def dom_id = "live_#{@section}"
  def section = @section

  # Before the first shot there is no card row yet; show an empty Card 1 anyway,
  # so the range screen looks the same from Start onward and shots just appear.
  def card_number = @card&.number || 1

  def shots = @card ? @card.shots.to_a : []
  def scored = shots.select(&:scored?)
  def latest = scored.last
  def stats = CardStats.new(scored, @session.target_spec)
  def spec = @session.target_spec
  def earlier_cards = @card ? @session.cards.to_a - [ @card ] : []

  # The latest shot's arrow: CSS degrees clockwise from pointing right (screen y
  # is down, target y is UP), or nil when the shot reads "center" (a dot instead).
  def direction_angle(shot)
    return if shot.direction.nil? || shot.direction == "center"

    -Math.atan2(shot.final_y_mm, shot.final_x_mm) * 180.0 / Math::PI
  end
end
