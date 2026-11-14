# The Scoring model page's charts: the engine's rules and the learned model side by
# side, one point per step along x (a training, or a live session), as percentages.
# Server SVG like the journal's; each point's numbers on hover (an SVG <title>),
# the tables below are the same data.
#
#   render(ModelChartComponent.new(label: "...", points: [
#     { label: "Nov 13", engine: 90.0, model: 96.7, title: "54 vs 58 of 60" }, ...]))
class ModelChartComponent < ApplicationComponent
  W, H = 800, 220
  LEFT, RIGHT, TOP, BOTTOM = 44, 16, 14, 28
  SERIES = { engine: "text-gray-500 dark:text-gray-400", model: "text-blue-600 dark:text-blue-400" }.freeze
  GRID = "text-gray-200 dark:text-gray-800"

  def initialize(label:, points:, unit: "%")
    @label, @points, @unit = label, points, unit
  end

  def call
    tag.div(class: "overflow-x-auto") do
      safe_join([
        tag.svg(viewBox: "0 0 #{W} #{H}", role: "img", "aria-label": @label, class: "h-auto w-full min-w-[32rem]",
                xmlns: "http://www.w3.org/2000/svg", "font-family": "system-ui, sans-serif") do
          safe_join([ grid, SERIES.keys.map { series(it) }, x_labels ].flatten.compact)
        end,
        legend
      ])
    end
  end

  private
    def values = @points.flat_map { [ it[:engine], it[:model] ] }.compact

    def y_range
      @y_range ||= begin
        lo, hi = values.minmax
        lo = [ ((lo - 2) / 5.0).floor * 5, 0 ].max
        hi = @unit == "%" ? [ ((hi + 2) / 5.0).ceil * 5, 100 ].min : ((hi * 1.15) * 10).ceil / 10.0
        hi = lo + 5 if hi <= lo
        [ lo.to_f, hi.to_f ]
      end
    end

    def x(i) = @points.size == 1 ? (LEFT + W - RIGHT) / 2.0 : LEFT + (W - LEFT - RIGHT) * i / (@points.size - 1).to_f
    def y(v) = (TOP + (H - TOP - BOTTOM) * (1 - (v - y_range[0]) / (y_range[1] - y_range[0]))).round(1)
    def fmt(v) = @unit == "%" ? "#{v.round}%" : format("%.2f", v)

    def grid
      lo, hi = y_range
      steps = 4
      (0..steps).map do |k|
        v = lo + (hi - lo) * k / steps
        tag.g(class: GRID) do
          safe_join([ tag.line(x1: LEFT, x2: W - RIGHT, y1: y(v), y2: y(v), stroke: "currentColor", "stroke-width": 1),
                      tag.text(fmt(v), x: LEFT - 6, y: y(v) + 4, "text-anchor": "end", "font-size": 11,
                                       class: "fill-gray-500 dark:fill-gray-400") ])
        end
      end
    end

    def series(key)
      pts = @points.each_with_index.filter_map { |p, i| [ i, p ] if p[key] }
      return if pts.empty?

      tag.g(class: SERIES[key]) do
        safe_join([
          (tag.polyline(points: pts.map { |i, p| "#{x(i)},#{y(p[key])}" }.join(" "), fill: "none", stroke: "currentColor",
                        "stroke-width": 2) if pts.size > 1),
          pts.map do |i, p|
            tag.circle(cx: x(i), cy: y(p[key]), r: 4.5, fill: "currentColor") do
              tag.title("#{key == :model ? "Model" : "Engine"}: #{fmt(p[key])}#{" - #{p[:title]}" if p[:title]}")
            end
          end
        ].flatten.compact)
      end
    end

    def x_labels
      every = (@points.size / 10.0).ceil.clamp(1, nil)
      @points.each_with_index.filter_map do |p, i|
        next unless (i % every).zero? || i == @points.size - 1

        tag.text(p[:label], x: x(i), y: H - 8, "text-anchor": "middle", "font-size": 11, class: "fill-gray-500 dark:fill-gray-400")
      end
    end

    def legend
      tag.p(class: "mt-1 flex gap-4 text-sm text-gray-600 dark:text-gray-300") do
        safe_join(SERIES.map do |key, colour|
          tag.span(class: "flex items-center gap-1.5") do
            safe_join([ tag.span(class: "inline-block size-2.5 rounded-full bg-current #{colour}"),
                        key == :model ? "Model" : "Engine's rules" ])
          end
        end)
      end
    end
end
