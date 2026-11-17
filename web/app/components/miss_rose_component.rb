# "Where the misses go": the misses (8 or worse) by direction from the centre,
# as 8 wedges around the bull - each wedge's length is its share of the misses.
# The latest group (Journal#miss_rows, first row) is filled; the one before it,
# when there is one, a dashed outline, so a habit growing or fading shows. The
# table under it is the same numbers, readable without the picture.
#
#   render(MissRoseComponent.new(rows: journal.miss_rows))
#   row = { label: "Last 5 sessions", misses: 120, counts: { "low left" => 30, ... } }
class MissRoseComponent < ApplicationComponent
  SIZE = 360
  C = SIZE / 2.0
  R = 105.0                  # the biggest share's wedge
  HALF = 19.0                # degrees each side of a wedge's direction (a gap between them)
  # Clockwise from the top, as a shooter reads a target.
  ORDER = [ "high", "high right", "right", "low right", "low", "low left", "left", "high left" ].freeze
  ANGLE = TargetSpec::DIRECTIONS.each_with_index.to_h { |d, i| [ d, i * 45.0 ] }.freeze   # 0 = right, counter-clockwise
  MARK = "text-blue-600 dark:text-blue-400"
  INK = "text-gray-500 dark:text-gray-400"
  GRID = "text-gray-200 dark:text-gray-800"
  PAPER = { MARK => "text-blue-600", INK => "text-gray-500", GRID => "text-gray-200" }.freeze

  def initialize(rows:, paper: false)
    @rows, @paper = rows.first(2), paper
  end

  def render? = @rows.any?

  def share(row, dir) = row[:counts][dir].to_f / row[:misses]
  def top = @top ||= @rows.flat_map { |r| ORDER.map { share(r, it) } }.max.then { it.positive? ? it : 1.0 }
  def pct(row, dir) = "#{(share(row, dir) * 100).round}%"

  # The direction most of the latest misses go, for the sentence over the picture.
  def worst = ORDER.max_by { share(@rows.first, it) }

  def call
    tag.div(class: "space-y-3") do
      safe_join([ summary, rose, table ])
    end
  end

  private
    def ink_class(key) = @paper ? PAPER[key] : key

    def summary
      row = @rows.first
      tag.p(class: "text-sm") do
        safe_join([ "#{row[:label]}: most misses go ", tag.strong("#{worst} (#{pct(row, worst)})"),
                    " of #{row[:misses]} shots scoring 8 or worse." ])
      end
    end

    def point(deg, r) = [ (C + r * Math.cos(deg * Math::PI / 180)).round(1), (C - r * Math.sin(deg * Math::PI / 180)).round(1) ]

    def wedge(dir, r)
      a = ANGLE.fetch(dir)
      x1, y1 = point(a - HALF, r)
      x2, y2 = point(a + HALF, r)
      "M#{C} #{C} L#{x1} #{y1} A#{r.round(1)} #{r.round(1)} 0 0 0 #{x2} #{y2} Z"
    end

    def radius(row, dir) = R * share(row, dir) / top

    def rose
      latest, before = @rows
      parts = []
      parts << tag.g(class: ink_class(GRID)) do
        safe_join([ 0.5, 1.0 ].map { tag.circle(cx: C, cy: C, r: R * it, fill: "none", stroke: "currentColor", "stroke-width": 1) })
      end
      parts << tag.g(class: ink_class(MARK)) do
        safe_join(ORDER.filter_map do |dir|
          next if latest[:counts][dir].zero?

          tag.path(d: wedge(dir, radius(latest, dir)), fill: "currentColor", "fill-opacity": 0.75) do
            tag.title("#{latest[:label]}: #{dir} #{pct(latest, dir)} (#{latest[:counts][dir]})")
          end
        end)
      end
      if before
        parts << tag.g(class: ink_class(INK)) do
          safe_join(ORDER.filter_map do |dir|
            next if before[:counts][dir].zero?

            tag.path(d: wedge(dir, radius(before, dir)), fill: "none", stroke: "currentColor", "stroke-width": 1.5, "stroke-dasharray": "4 3")
          end)
        end
      end
      parts << tag.g(class: ink_class(INK)) do
        safe_join(ORDER.map do |dir|
          x, y = point(ANGLE.fetch(dir), R + 24)
          cos = Math.cos(ANGLE.fetch(dir) * Math::PI / 180)
          anchor = cos.abs < 0.3 ? "middle" : (cos.positive? ? "start" : "end")
          tag.text(dir, x:, y: y + 4, "text-anchor": anchor, "font-size": 13, fill: "currentColor")
        end)
      end
      tag.svg(viewBox: "-40 32 #{SIZE + 80} #{SIZE - 56}", role: "img", xmlns: "http://www.w3.org/2000/svg",
              "aria-label": "Misses by direction: #{ORDER.map { "#{it} #{pct(latest, it)}" }.join(', ')}",
              class: "mx-auto h-auto w-full max-w-md", "font-family": "system-ui, sans-serif") { safe_join(parts) }
    end

    def table
      muted = @paper ? "text-gray-500" : "text-gray-500 dark:text-gray-400"
      tag.div(class: @paper ? "" : "overflow-x-auto") do
        tag.table(class: "w-full min-w-[34rem] text-center text-sm tabular-nums") do
          safe_join([
            tag.thead(tag.tr(safe_join([ tag.th(tag.span("Sessions", class: "sr-only")) ] +
                                       ORDER.map { tag.th(it, scope: "col", class: "px-1 pb-1 font-medium #{muted}") }))),
            tag.tbody(safe_join(@rows.each_with_index.map do |row, i|
              tag.tr(safe_join([ tag.th(scope: "row", class: "pr-3 text-left font-medium whitespace-nowrap") do
                                   safe_join([ tag.span(i.zero? ? "■ " : "┅ ", class: ink_class(i.zero? ? MARK : INK), "aria-hidden": true), row[:label],
                                               tag.span("#{row[:misses]} misses", class: "block text-xs font-normal #{muted}") ])
                                 end ] +
                               ORDER.map { |dir| tag.td(row[:counts][dir].zero? ? "–" : pct(row, dir), class: "px-1 py-1 #{'font-semibold' if dir == worst && i.zero?}") }))
            end))
          ])
        end
      end
    end
end
