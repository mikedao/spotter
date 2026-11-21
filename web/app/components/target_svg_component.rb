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

  # in_order: number the shots 1, 2, 3... in firing order (a whole session on one
  # target, where card numbers would repeat); a match's own numbers win.
  # group_of: the card is shot in runs of that many (5-shot groups without changing
  # the card): the CURRENT run is drawn as usual with its group marks and its widest
  # pair measured on the target; earlier runs on the card fade back.
  def initialize(spec:, shots: [], latest: nil, zoom: :fit, label: "Target", in_order: false, group_of: nil)
    @spec = spec
    @shots = shots.select { |s| s.final_x_mm && s.final_y_mm }
    @latest = latest
    @zoom = zoom
    @label = label
    @order = in_order ? @shots.sort_by(&:fired_at).each_with_index.to_h { |s, i| [ s.id, i + 1 ] } : {}
    @group = (CardStats.new(@shots, @spec).current_group(of: group_of) if group_of)
  end

  GROUP_LINE = "#dc2626"   # the widest pair, as the group marks

  def call
    tag.svg(viewBox: view_box, role: "img", "aria-label": @label, class: "h-auto w-full",
            xmlns: "http://www.w3.org/2000/svg") do
      safe_join([ backdrop, rings, ring_numbers, group_marks, shot_marks ].flatten.compact)
    end
  end

  private
    # Half the view's width in mm: ring n's radius plus a margin of half a ring,
    # for the innermost n from the black outward that holds every shot (the view
    # is square, so a shot fits when both |x| and |y| do).
    def half_extent = @spec.ring_radius_mm(view_ring) + @spec.step_mm / 2.0

    # The outermost ring in view.
    def view_ring
      @view_ring ||= if @zoom == :card then 1
      else
        margin = @spec.step_mm / 2.0
        far = @shots.map { |s| [ s.final_x_mm.abs, s.final_y_mm.abs ].max }.max.to_f + TargetSpec::PELLET_MM / 2.0 + 0.5
        @spec.black_ring.downto(1).find { far <= @spec.ring_radius_mm(it) + margin } || 1
      end
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

    # As printed on an ISSF card: 1-8 in the middle of each ring's band, on the four
    # axes (9 and 10 unnumbered); pale on the black. Sized to the band, so they
    # read the same on pistol and rifle and grow with the zoom.
    def ring_numbers
      size = (@spec.step_mm * 0.45).round(2)
      (view_ring..8).flat_map do |n|   # the next band out sits on the view's edge: unnumbered
        mid = ((@spec.ring_radius_mm(n) + @spec.ring_radius_mm(n + 1)) / 2.0).round(2)
        colour = @spec.ring_radius_mm(n) <= @spec.black_radius_mm + 0.01 ? LINE_ON_BLACK : LINE_ON_PAPER
        [ [ -mid, 0 ], [ mid, 0 ], [ 0, -mid ], [ 0, mid ] ].map do |x, y|
          tag.text(n, x:, y: (y + size * 0.36).round(2), "text-anchor": "middle", "font-size": size,
                   "font-weight": 600, fill: colour, "font-family": "system-ui, sans-serif", "aria-hidden": true)
        end
      end
    end

    # The shots the group marks describe: the current group when shooting in runs.
    def grouped = @group ? @group.shots : @shots

    def faded?(shot) = @group && !@group.shots.include?(shot)

    def group_marks
      return [] if grouped.size < 2

      stats = CardStats.new(grouped, @spec)
      mx, my = stats.mean_point
      arm = 2.5
      [
        tag.circle(cx: mx, cy: -my, r: stats.mean_radius_mm, fill: "none", stroke: FLAGGED, "stroke-width": 0.35,
                   "stroke-dasharray": "1.2 0.8", opacity: 0.8),
        tag.path(d: "M#{mx - arm} #{-my}H#{mx + arm}M#{mx} #{-my - arm}V#{-my + arm}", stroke: FLAGGED, "stroke-width": 0.5),
        widest_pair(stats)
      ].compact
    end

    # Shooting in runs: the line the group size is measured along, centre to
    # centre between the two shots farthest apart, and the size beside it (with a
    # white halo, so it reads on the paper and on the black).
    def widest_pair(stats)
      return unless @group

      a, b = stats.widest_pair
      x1, y1, x2, y2 = [ a.final_x_mm, -a.final_y_mm, b.final_x_mm, -b.final_y_mm ].map { it.round(2) }
      size = (@spec.step_mm * 0.2).clamp(1.2, 3.2).round(2)
      label = "#{@group.size_mm} mm"
      tag.g("data-group-size": @group.size_mm) do
        safe_join([
          tag.line(x1:, y1:, x2:, y2:, stroke: GROUP_LINE, "stroke-width": 0.45, "stroke-linecap": "round"),
          tag.text(label, x: ((x1 + x2) / 2).round(2), y: (((y1 + y2) / 2) - size * 0.6).round(2), "text-anchor": "middle",
                   "font-size": size, "font-weight": 700, fill: GROUP_LINE, stroke: "#fff", "stroke-width": (size * 0.18).round(2),
                   "paint-order": "stroke", "font-family": "system-ui, sans-serif")
        ])
      end
    end

    def shot_marks
      r = TargetSpec::PELLET_MM / 2.0
      # Faded (earlier groups) first, the latest last: the current group on top.
      @shots.sort_by { [ faded?(it) ? 0 : 1, it == @latest ? 1 : 0 ] }.flat_map do |s|
        x, y = s.final_x_mm.round(2), -s.final_y_mm.round(2)
        # A sighter is grey and marked "S"; in a match or final a shot shows its
        # number in the event, otherwise its number on the card.
        fill = s.sighter? ? SIGHTER : (s.flagged? && !s.called? ? FLAGGED : SHOT)
        fill = SIGHTER if faded?(s)
        [
          (tag.circle(cx: x, cy: y, r: r + 1.1, fill: "none", stroke: LATEST, "stroke-width": 0.7) if s == @latest),
          tag.circle(cx: x, cy: y, r: r, fill: fill, "fill-opacity": faded?(s) ? 0.35 : 0.88, stroke: "#fff", "stroke-width": 0.3,
                     "data-faded": (true if faded?(s))),
          tag.text(s.sighter? ? "S" : (s.match_number || @order[s.id] || s.number), x: x, y: y + 0.95, "text-anchor": "middle", "font-size": 2.7, "font-weight": 700,
                   fill: "#fff", "fill-opacity": (0.7 if faded?(s)), "font-family": "system-ui, sans-serif")
        ].compact
      end
    end
end
