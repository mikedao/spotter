# A journal trend chart, drawn on the server as SVG (like the target), one session
# per step along x, oldest on the left:
#   :line  - one value per session (score per 60), matches as filled dots and
#            practice as hollow ones, with the goal as a dashed line
#   :range - each session's worst-to-best 10-shot series as a bar, its mean a dot,
#            the goal's pace per series as a dashed line
# Each session is a link to it, with its numbers on hover (an SVG <title>); the
# session list below is the same data as a table.
#
#   render(JournalChartComponent.new(kind: :line, points:, goal: 565, goal_label: "Goal 565"))
#   point = { label: "Nov 12", y: 571, low: nil, high: nil, filled: true, title: "...", href: "/practice/3" }
class JournalChartComponent < ApplicationComponent
  W, H = 800, 240
  LEFT, RIGHT, TOP, BOTTOM = 44, 84, 14, 28   # the goal's label sits in the right margin, clear of the data
  MARK = "text-blue-600 dark:text-blue-400"
  INK = "text-gray-500 dark:text-gray-400"
  GRID = "text-gray-200 dark:text-gray-800"
  # paper: true (the printed report) - light only, whatever the system setting.
  PAPER = { MARK => "text-blue-600", INK => "text-gray-500", GRID => "text-gray-200" }.freeze

  # max: the most possible (600 per 60, 100 per series), so the axis never runs past it.
  def initialize(kind:, points:, label:, max:, goal: nil, goal_label: nil, paper: false)
    @kind, @points, @goal, @goal_label, @label, @max, @paper = kind, points, goal, goal_label, label, max, paper
  end

  def call
    tag.div(class: @paper ? "[--chart-surface:#fff]" : "overflow-x-auto [--chart-surface:#fff] dark:[--chart-surface:#111827]") do   # the card behind: hollow dots
      tag.svg(viewBox: "0 0 #{W} #{H}", role: "img", "aria-label": @label, class: @paper ? "h-auto w-full" : "h-auto w-full min-w-[36rem]",
              xmlns: "http://www.w3.org/2000/svg", "font-family": "system-ui, sans-serif") do
        safe_join([ grid, goal_line, marks, x_labels ].flatten.compact)
      end
    end
  end

  private
    def mark = @paper ? PAPER[MARK] : MARK
    def ink = @paper ? PAPER[INK] : INK
    def grid_ink = @paper ? PAPER[GRID] : GRID

    def values = @points.flat_map { [ it[:y], it[:low], it[:high] ] }.compact + [ @goal ].compact

    # Round the y range out to tidy steps, with a little room above and below.
    def y_range
      @y_range ||= begin
        lo, hi = values.minmax
        step = nice_step((hi - lo).abs.clamp(4, nil) / 4.0)
        top = [ ((hi + step / 2.0) / step).ceil * step, @max ].min
        [ ((lo - step / 2.0) / step).floor * step, top, step ]
      end
    end

    def nice_step(raw)
      mag = 10**Math.log10(raw).floor
      [ 1, 2, 2.5, 5, 10 ].map { it * mag }.find { it >= raw }
    end

    def x(i) = @points.size == 1 ? (LEFT + W - RIGHT) / 2.0 : LEFT + (W - LEFT - RIGHT) * i / (@points.size - 1).to_f
    def y(v) = (TOP + (H - TOP - BOTTOM) * (1 - (v - y_range[0]) / (y_range[1] - y_range[0]).to_f)).round(1)
    def fmt(v) = v == v.round ? v.round.to_s : v.round(1).to_s

    def grid
      lo, hi, step = y_range
      (0..((hi - lo) / step).round).map { lo + it * step }.flat_map do |v|
        [ tag.line(x1: LEFT, x2: W - RIGHT, y1: y(v), y2: y(v), stroke: "currentColor", "stroke-width": 1, class: grid_ink),
          tag.text(fmt(v), x: LEFT - 8, y: y(v) + 4, "text-anchor": "end", "font-size": 12, fill: "currentColor", class: ink) ]
      end
    end

    def goal_line
      return [] unless @goal

      [ tag.line(x1: LEFT, x2: W - RIGHT, y1: y(@goal), y2: y(@goal), stroke: "currentColor", "stroke-width": 1.5,
                 "stroke-dasharray": "6 4", class: ink),
        tag.text(x: W - RIGHT + 8, y: y(@goal) - 2, "font-size": 12, "font-weight": 600, fill: "currentColor", class: ink) do
          safe_join(@goal_label.split("\n").each_with_index.map { |line, i| tag.tspan(line, x: W - RIGHT + 8, dy: i.zero? ? 0 : 14) })
        end ]
    end

    def marks
      tag.g(class: mark) do
        safe_join([ (trend_line if @kind == :line), *@points.each_with_index.map { |p, i| point(p, i) } ].compact)
      end
    end

    def trend_line
      return if @points.size < 2

      d = @points.each_with_index.map { |p, i| "#{i.zero? ? 'M' : 'L'}#{x(i).round(1)} #{y(p[:y])}" }.join
      tag.path(d:, fill: "none", stroke: "currentColor", "stroke-width": 2, "stroke-linejoin": "round")
    end

    # A dot (filled = match, hollow = practice; the hollow is ringed in the card's
    # own colour behind it), a series range bar under it, and a wider invisible
    # target for the hover title and the link.
    def point(p, i)
      cx = x(i).round(1)
      parts = []
      parts << tag.line(x1: cx, x2: cx, y1: y(p[:low]), y2: y(p[:high]), stroke: "currentColor", "stroke-width": 4,
                        "stroke-linecap": "round", opacity: 0.45) if p[:low] && p[:high]
      parts << tag.circle(cx:, cy: y(p[:y]), r: 4.5, fill: p[:filled] == false ? "var(--chart-surface)" : "currentColor",
                          stroke: "currentColor", "stroke-width": 2)
      parts << tag.circle(cx:, cy: y(p[:y]), r: 14, fill: "transparent") { tag.title(p[:title]) }
      link_to(safe_join(parts), p[:href], "aria-label": p[:title])
    end

    # Dates under the axis: the first, the last, and evenly between (at most 6).
    def x_labels
      n = @points.size
      shown = n <= 6 ? (0...n).to_a : (0..5).map { (it * (n - 1) / 5.0).round }.uniq
      shown.map do |i|
        anchor = n == 1 ? "middle" : (i.zero? ? "start" : (i == n - 1 ? "end" : "middle"))
        tag.text(@points[i][:label], x: x(i).round(1), y: H - 8, "text-anchor": anchor, "font-size": 12, fill: "currentColor", class: ink)
      end
    end
end
