# Group training (5-shot groups shot on one card, PracticeSession#group_of): what
# the session was about is the size of each group, not a score. Each group on its
# own small target, each framed on itself (one wide group would shrink the rest to
# dots), with the widest pair drawn and the size under it; the best group outlined. The numbers
# up top and the footer are group sizes: how many, the best, the average.
# Past MAX_GROUPS the last cell says "+ N more".
class SharePicture::Groups < SharePicture
  MAX_GROUPS = 16
  FOOTER = 260
  LABEL_H = 84
  GAP = 36

  def filename = "spotter-groups.jpg"

  private
    def draw
      head, y = header("Groups of #{set.groups.first&.of || 5}")
      parts = [ head, tiles(y + 40) ]
      top = y + 40 + 230 + 50

      groups = set.groups
      shown = groups.size > MAX_GROUPS ? groups.first(MAX_GROUPS - 1) : groups
      cells = shown.size + (groups.size > shown.size ? 1 : 0)
      cols = case cells
      when 1 then 1
      when 2..4 then 2
      when 5..9 then 3
      else 4
      end
      size = [ (W - 2 * MARGIN - GAP * (cols - 1)) / cols.to_f, 900 ].min
      left = (W - cols * size - (cols - 1) * GAP) / 2.0
      rows = (cells / cols.to_f).ceil
      best = set.best_group

      shown.each_with_index do |group, i|
        x = left + (i % cols) * (size + GAP)
        gy = top + (i / cols) * (size + LABEL_H + GAP)
        if group == best
          parts << rect(x - 10, gy - 10, size + 20, size + 20, t.highlight, rx: 12)
        else
          parts << rect(x - 6, gy - 6, size + 12, size + 12, t.edge, rx: 10, opacity: t.edge_op)
        end
        parts << target(x, gy, size, group.shots, numbers: cols <= 3, extra: widest_pair(group))
        parts << label(group, x, gy + size, size, group == best)
      end
      if cells > shown.size
        i = shown.size
        x = left + (i % cols) * (size + GAP)
        gy = top + (i / cols) * (size + LABEL_H + GAP)
        parts << rect(x, gy, size, size, t.row, rx: 10, opacity: t.row_op, stroke: t.edge, stroke_width: 2, stroke_opacity: t.edge_op)
        more = "+ #{groups.size - shown.size} more"
        parts << text(x + size / 2.0, gy + size / 2.0 + 20, more, ShareSvg.fit_size(more, 64, size - 40, 24), t.text, weight: 800, anchor: "middle")
      end

      height = [ (top + rows * (size + LABEL_H + GAP) + FOOTER).ceil, 1400 ].max
      parts << footer_groups(height)
      [ parts.join, height ]
    end

    # Three tiles: how many groups, the best, the average (complete groups only).
    def tiles(top)
      best = set.best_group
      values = [
        [ "Groups", set.complete_groups.size.to_s, "of #{set.groups.first&.of || 5} shots" ],
        [ "Best", best ? "#{best.size_mm} mm" : "–", best ? best.label : "" ],
        [ "Average", set.mean_group_mm ? "#{set.mean_group_mm} mm" : "–", "center to center" ]
      ]
      gap = 36
      w = (W - 2 * MARGIN - 2 * gap) / 3.0
      h = 230
      values.each_with_index.map do |(label, value, sub), i|
        x = MARGIN + i * (w + gap)
        value_size = ShareSvg.fit_size(value, 88, w - 60, 40)
        [ rect(x, top, w, h, t.row, rx: 22, opacity: t.row_op, stroke: t.edge, stroke_width: 2, stroke_opacity: t.edge_op),
          eyebrow(x + 30, top + 56, label, 26, t.star),
          text(x + 30, top + 150, value, value_size, t.text, weight: 800),
          text(x + 30, top + 200, sub, ShareSvg.fit_size(sub, 30, w - 60, 20), t.sub, opacity: 0.85) ].join
      end.join
    end

    # The line the size is measured along, centre to centre, in the target's mm (y down).
    def widest_pair(group)
      return if group.shots.size < 2

      a, b = CardStats.new(group.shots, set.spec).widest_pair
      %(<line x1="#{a.final_x_mm.round(2)}" y1="#{(-a.final_y_mm).round(2)}" x2="#{b.final_x_mm.round(2)}" y2="#{(-b.final_y_mm).round(2)}" ) +
        %(stroke="#{shot_colour}" stroke-width="0.9" stroke-linecap="round" stroke-opacity="0.95"/>)
    end

    def label(group, x, y, size, best)
      value = group.size_mm ? "#{group.size_mm} mm" : "–"
      value += " (#{group.shots.size} of #{group.of})" unless group.complete
      value_size = ShareSvg.fit_size(value, 50, size * 0.62, 24)
      name = best ? "#{group.label} · best" : group.label
      name_size = ShareSvg.fit_size(name, 34, size - tw(value, value_size) - 24, 18)
      base = y + 62
      [ text(x, base, name, name_size, best ? t.highlight : t.sub, weight: 700),
        text(x + size, base, value, value_size, t.text, weight: 800, anchor: "end") ].join
    end

    # Best group large on the left (the average beside it), Spotter's mark on the right.
    def footer_groups(bottom)
      y = bottom - 90
      best = set.best_group
      main = best ? "#{best.size_mm} mm" : "–"
      parts = [ eyebrow(MARGIN, y - 92, "Best group", 28, t.muted) ]
      parts << text(MARGIN, y, main, 96, t.text, weight: 800)
      if set.mean_group_mm
        parts << text(MARGIN + tw(main, 96) + 24, y, "avg #{set.mean_group_mm} mm", 48, t.star, weight: 700)
      end
      parts << ShareSvg.brand(W - MARGIN, y - 30, 64, t)
      parts.join
    end
end
