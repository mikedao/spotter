# The target drawn as SVG on the server, in millimetres, with the shots on it
# (after fl-shooters' MatchGroupComponent: no JavaScript, so it streams over Turbo
# like any other HTML). Shots are drawn at true pellet size at their FINAL position
# (the shooter's call wins), numbered, flagged ones in red, the latest ringed.
# With two or more shots the mean point of impact is a cross and the mean radius a
# dashed circle about it.
#
#   render(TargetSvgComponent.new(spec:, shots:, latest:))
#
# zoom: :fit (default) frames the black aiming mark and steps out a WHOLE ring at
# a time, only as far as needed to show every shot in full - so the group is big
# and the scale only changes when a shot lands further out (live, on each shot).
# :card always shows out to ring 1.
class TargetSvgComponent < ApplicationComponent
  PAPER = "#f6f1e7"
  LINE_ON_PAPER = "#4a3b2f"     # brown on the paper, pale on the black (fl-shooters' finding)
  LINE_ON_BLACK = "#d6d3d1"
  SHOT = "#2563eb"
  FLAGGED = "#dc2626"
  SIGHTER = "#6b7280"
  LATEST = "#f59e0b"

  def initialize(spec:, shots: [], latest: nil, zoom: :fit, label: "Target")
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
    # Half the view's width in mm: ring n's radius plus a margin of half a ring,
    # for the innermost n from the black outward that holds every shot (the view
    # is square, so a shot fits when both |x| and |y| do).
    def half_extent
      margin = @spec.step_mm / 2.0
      return @spec.ring_radius_mm(1) + margin if @zoom == :card

      far = @shots.map { |s| [ s.final_x_mm.abs, s.final_y_mm.abs ].max }.max.to_f + TargetSpec::PELLET_MM / 2.0 + 0.5
      ring = @spec.black_ring.downto(1).find { far <= @spec.ring_radius_mm(it) + margin } || 1
      @spec.ring_radius_mm(ring) + margin
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
        # A sighter is grey and marked "S"; in a match or final a shot shows its
        # number in the event, otherwise its number on the card.
        fill = s.sighter? ? SIGHTER : (s.flagged? && !s.called? ? FLAGGED : SHOT)
        [
          (tag.circle(cx: x, cy: y, r: r + 1.1, fill: "none", stroke: LATEST, "stroke-width": 0.7) if s == @latest),
          tag.circle(cx: x, cy: y, r: r, fill: fill, "fill-opacity": 0.88, stroke: "#fff", "stroke-width": 0.3),
          tag.text(s.sighter? ? "S" : (s.match_number || s.number), x: x, y: y + 0.95, "text-anchor": "middle", "font-size": 2.7, "font-weight": 700,
                   fill: "#fff", "font-family": "system-ui, sans-serif")
        ].compact
      end
    end
end
