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
  # A phone held sideways (short:): the left column, the window's whole height -
  # but on a narrow phone leaving the right column ~19rem (the header's buttons).
  # An iPad upright (tall:): leave room below for a row of panels (latest shot,
  # clock) on the first screen.
  TARGET_SIZE = "mx-auto w-full max-w-[calc(100svh_-_7.5rem)] min-w-72 wide:w-[min(calc(100svh_-_7.5rem),60rem)] " \
                "wide:sticky wide:top-4 tall:max-w-[min(calc(100svh_-_24rem),60rem)] " \
                "short:col-start-1 short:row-span-2 short:row-start-1 short:sticky short:top-2 short:mx-0 " \
                "short:w-[min(calc(100svh_-_1.25rem),calc(100vw_-_23rem))] short:max-w-none short:min-w-0".freeze

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
  def stats = CardStats.new(scored, @session.target_spec, whole_rings: @session.whole_rings?)
  def spec = @session.target_spec
  def earlier_cards = @card ? @session.cards.to_a - [ @card ] : []

  # Shooting in runs (a plan block's 5-shot groups, the card not changed between):
  # the card's runs in firing order, the last one being shot.
  def group_of = @session.group_of
  def groups = (@groups ||= group_of ? stats.groups(of: group_of) : [])

  # One shot as a whole-ring chip linking to its page (your call wins; penalized
  # = a struck 0). Same colours as the target: the latest ringed in amber, red =
  # flagged and not yet checked by you.
  def chip(shot)
    value = shot.penalized? ? 0 : shot.final_ring
    link_to value, helpers.shot_path(shot),
            "aria-label": "#{shot.stage_label || "Shot #{shot.number}"}: #{value}",
            class: classes("grid h-9 min-w-9 place-items-center rounded-md border px-1.5 text-lg font-semibold tabular-nums hover:bg-gray-100 dark:hover:bg-gray-800",
                           if shot.penalized? then "border-gray-300 text-gray-500 line-through dark:border-gray-700"
                           elsif shot.flagged? && !shot.called? then "border-red-500 text-red-700 dark:border-red-500 dark:text-red-300"
                           else "border-gray-300 dark:border-gray-700"
                           end,
                           ("ring-2 ring-amber-500 ring-offset-1 ring-offset-white dark:ring-offset-gray-900" if shot == latest))
  end

  # The card's most recent capture, when it wasn't scored and can still be
  # plotted (it has a picture): the range screen offers to plot it.
  def unplotted_capture
    last = shots.max_by(&:fired_at)
    last if last&.unscored? && last.after_image.attached? && @session.live?
  end

  # The latest shot's arrow: CSS degrees clockwise from pointing right (screen y
  # is down, target y is UP), or nil when the shot reads "center" (a dot instead).
  def direction_angle(shot)
    return if shot.direction.nil? || shot.direction == "center"

    -Math.atan2(shot.final_y_mm, shot.final_x_mm) * 180.0 / Math::PI
  end
end
