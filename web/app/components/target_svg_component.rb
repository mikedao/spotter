# The target drawn as SVG on the server, in millimetres, with the shots on it
# (after fl-shooters' MatchGroupComponent: no JavaScript, so it streams over Turbo
# like any other HTML). Shots are drawn at true pellet size at their FINAL position
# (the shooter's call wins), numbered, flagged ones in red, the latest ringed.
# With two or more shots the mean point of impact is a cross and the mean radius a
# dashed circle about it.
#
#   render(TargetSvgComponent.new(spec:, shots:, latest:, zoom: :group))
#
# zoom: :card shows out to ring 1; :group frames the shots.
class TargetSvgComponent < ApplicationComponent
  PAPER = "#f6f1e7"
  LINE_ON_PAPER = "#4a3b2f"     # brown on the paper, pale on the black (fl-shooters' finding)
  LINE_ON_BLACK = "#d6d3d1"
  SHOT = "#2563eb"
  FLAGGED = "#dc2626"
  LATEST = "#f59e0b"

  def initialize(spec:, shots: [], latest: nil, zoom: :card, label: "Target")
    @spec = spec
    @shots = shots.select { |s| s.final_x_mm && s.final_y_mm }
    @latest = latest
    @zoom = zoom
    @label = label
  end

  def call
    tag.svg(viewBox: view_box, role: "img", "aria-label": @label, class: "h-auto w-full",
            xmlns: "http://www.w3.org/2000/svg") do
      safe_join([ backdrop, rings, group_marks, shot_marks ].flatten.compact)
    end
  end

  private
    def half_extent
      outer = @spec.ring_radius_mm(1) + 4
      return outer unless @zoom == :group && @shots.any?

      far = @shots.map { |s| [ s.final_x_mm.abs, s.final_y_mm.abs ].max }.max + TargetSpec::PELLET_MM + 4
      far.clamp(@spec.ring_radius_mm(9) + 2, outer)
    end

    def view_box
      h = half_extent.round(2)
      "#{-h} #{-h} #{2 * h} #{2 * h}"
    end

    def backdrop = tag.rect(x: -200, y: -200, width: 400, height: 400, fill: PAPER)

    def rings
      black_r = @spec.black_radius_mm
      parts = [ tag.circle(cx: 0, cy: 0, r: black_r, fill: "#111") ]
      (1..10).each do |n|
        r = @spec.ring_radius_mm(n)
        colour = r < black_r - 0.01 ? LINE_ON_BLACK : LINE_ON_PAPER
        parts << tag.circle(cx: 0, cy: 0, r: r, fill: "none", stroke: colour, "stroke-width": 0.25)
      end
      parts << tag.circle(cx: 0, cy: 0, r: @spec.inner_ten_radius_mm, fill: "none", stroke: LINE_ON_BLACK, "stroke-width": 0.2)
      parts
    end

    def group_marks
      return [] if @shots.size < 2

      stats = CardStats.new(@shots, @spec)
      mx, my = stats.mean_point
      arm = 2.5
      [
        tag.circle(cx: mx, cy: -my, r: stats.mean_radius_mm, fill: "none", stroke: FLAGGED, "stroke-width": 0.35,
                   "stroke-dasharray": "1.2 0.8", opacity: 0.8),
        tag.path(d: "M#{mx - arm} #{-my}H#{mx + arm}M#{mx} #{-my - arm}V#{-my + arm}", stroke: FLAGGED, "stroke-width": 0.5)
      ]
    end

    def shot_marks
      r = TargetSpec::PELLET_MM / 2.0
      @shots.sort_by { it == @latest ? 1 : 0 }.flat_map do |s|
        x, y = s.final_x_mm.round(2), -s.final_y_mm.round(2)
        fill = s.flagged? && !s.called? ? FLAGGED : SHOT
        [
          (tag.circle(cx: x, cy: y, r: r + 1.1, fill: "none", stroke: LATEST, "stroke-width": 0.7) if s == @latest),
          tag.circle(cx: x, cy: y, r: r, fill: fill, "fill-opacity": 0.88, stroke: "#fff", "stroke-width": 0.3),
          tag.text(s.number, x: x, y: y + 0.95, "text-anchor": "middle", "font-size": 2.7, "font-weight": 700,
                   fill: "#fff", "font-family": "system-ui, sans-serif")
        ].compact
      end
    end
end
