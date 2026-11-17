# "Where your shots land": one row per group of sessions (Journal#landing_rows),
# the share of its shots in each ring - X (inner ten), 10, 9, 8, 7, 6 or worse.
# Shading is by share across the whole grid, so rows compare at a glance; the
# numbers are in every cell, so it reads without colour too.
#
#   render(RingSpreadComponent.new(rows: journal.landing_rows))
#   row = { label: "Last 5 sessions", shots: 300, counts: { "X" => 31, "10" => 60, ... } }
class RingSpreadComponent < ApplicationComponent
  COLUMNS = SessionSummary::LANDING
  # The journal chart's blue (blue-600), as rgb for an alpha.
  BLUE = "37 99 235"

  def initialize(rows:, paper: false)
    @rows, @paper = rows, paper
  end

  def render? = @rows.any?

  def share(row, col) = row[:shots].positive? ? row[:counts][col].to_f / row[:shots] : 0.0
  def top = @top ||= @rows.flat_map { |r| COLUMNS.map { share(r, it) } }.max.then { it.positive? ? it : 1.0 }

  # Faint for a small share, full blue for the biggest one in the grid.
  def alpha(s) = (0.12 + 0.88 * s / top).round(2)
  def strong?(s) = alpha(s) >= 0.5

  def cell(row, col)
    s = share(row, col)
    return tag.td("–", class: "px-1 py-1 text-center #{muted}", "aria-label": "none") if row[:counts][col].zero?

    tag.td(class: "px-1 py-1") do
      tag.div("#{(s * 100).round}%", title: "#{row[:counts][col]} of #{row[:shots]} shots",
              class: "flex min-h-11 items-center justify-center rounded-md font-semibold tabular-nums #{strong?(s) ? 'text-white' : ''}",
              style: "background-color: rgb(#{BLUE} / #{alpha(s)})")
    end
  end

  def muted = @paper ? "text-gray-500" : "text-gray-500 dark:text-gray-400"

  def call
    tag.div(class: @paper ? "" : "overflow-x-auto") do
      tag.table(class: "w-full min-w-[30rem] table-fixed text-sm") do
        safe_join([
          tag.thead(tag.tr(safe_join([ tag.th(tag.span("Sessions", class: "sr-only"), class: "w-36") ] +
                                     COLUMNS.map { tag.th(it, scope: "col", class: "pb-1 text-center font-semibold") }))),
          tag.tbody(safe_join(@rows.map do |row|
            tag.tr(safe_join([ tag.th(scope: "row", class: "pr-3 text-left align-middle font-medium") do
                                 safe_join([ row[:label], tag.span("#{row[:shots]} shots", class: "block text-xs font-normal #{muted}") ])
                               end ] + COLUMNS.map { cell(row, it) }))
          end))
        ])
      end
    end
  end
end
