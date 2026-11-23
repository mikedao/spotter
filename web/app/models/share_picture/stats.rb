# The numbers of the set: six tiles (average, tens, inner tens, group, where the
# group sits, time), where the shots landed by ring as bars, and where the misses
# go as a rose of eight 45-degree directions (as fl-shooters' MissRoseComponent:
# shots of 8 or worse on pistol, 9 or worse on rifle; too few and it says so
# instead of showing a lean that isn't there).
class SharePicture::Stats < SharePicture
  HEIGHT = 2000
  MISS_MIN = 5

  private
    def draw
      head, y = header("The numbers")
      parts = [ head, tiles(y + 50) ]
      parts << split_bars(MARGIN, 1130, 640)
      parts << rose(1200, 1470, 230)
      parts << footer(HEIGHT)
      [ parts.join, HEIGHT ]
    end

    def tile_values
      stats = set.stats
      n = set.shots.size
      offset = (stats.mean_point_offset_mm if n >= 2)
      [
        [ "Average", average_text, "per shot" ],
        [ "10s", set.tens.to_s, "#{percent(set.tens, n)} of #{n} shots" ],
        [ "Inner tens", set.inner_tens.to_s, "#{percent(set.inner_tens, n)} of #{n} shots" ],
        [ "Group", set.group_mm ? "#{set.group_mm} mm" : "–", "per card, center to center" ],
        [ "Group center", offset ? "#{offset} mm" : "–", offset ? (offset < 1 ? "dead center" : stats.mean_point_direction) : "" ],
        [ "Time", duration(set.shooting_seconds), set.seconds_per_shot ? "#{set.seconds_per_shot} s between shots" : "" ]
      ]
    end

    def average_text
      avg = set.average
      return "–" unless avg

      format("%.2f", avg)
    end

    def percent(part, whole) = whole.positive? ? "#{(100.0 * part / whole).round}%" : "–"

    def duration(seconds)
      minutes = (seconds / 60.0).round
      minutes >= 60 ? "#{minutes / 60} h #{minutes % 60} min" : "#{minutes} min"
    end

    def tiles(top)
      gap = 36
      w = (W - 2 * MARGIN - 2 * gap) / 3.0
      h = 250
      tile_values.each_with_index.map do |(label, value, sub), i|
        x = MARGIN + (i % 3) * (w + gap)
        y = top + (i / 3) * (h + gap)
        value_size = ShareSvg.fit_size(value, 92, w - 60, 40)
        sub_size = ShareSvg.fit_size(sub, 30, w - 60, 20)
        [ rect(x, y, w, h, t.row, rx: 22, opacity: t.row_op, stroke: t.edge, stroke_width: 2, stroke_opacity: t.edge_op),
          eyebrow(x + 30, y + 58, label, 26, t.star),
          text(x + 30, y + 160, value, value_size, t.text, weight: 800),
          text(x + 30, y + 212, sub, sub_size, t.sub, opacity: 0.85) ].join
      end.join
    end

    # Where the shots landed, a bar per ring from the 10 out, as a share of every shot.
    def split_bars(x, top, width)
      rows = set.split
      n = [ set.shots.size, 1 ].max
      parts = [ eyebrow(x, top, "Where they landed", 30, t.highlight) ]
      row_h = 112
      label_w = 200
      track = width - label_w - 150
      rows.each_with_index do |(label, count), i|
        y = top + 50 + i * row_h
        share = count.to_f / n
        size = label.length > 2 ? 34 : 54
        parts << text(x, y + 62, label, size, t.text, weight: 800)
        parts << rect(x + label_w, y + 24, track, 50, t.text, rx: 12, opacity: 0.08)
        parts << rect(x + label_w, y + 24, [ track * share, share.positive? ? 12 : 0 ].max, 50, i.zero? ? t.highlight : t.text, rx: 12, opacity: (i.zero? ? nil : 0.75)) if share.positive?
        parts << text(x + width, y + 62, "#{(share * 100).round}%", 40, t.text, weight: 700, anchor: "end")
        parts << text(x + width, y + 96, "#{count} shot#{'s' unless count == 1}", 24, t.muted, anchor: "end")
      end
      parts.join
    end

    # Eight wedges, one per 45-degree direction, each wedge's AREA by its count (so the
    # radius goes with the square root), the count at its tip.
    def rose(cx, cy, radius)
      counts = set.misses_by_direction
      total = counts.sum
      parts = [ eyebrow(cx, cy - radius - 130, "Where the misses go", 30, t.highlight, anchor: "middle") ]
      parts << text(cx, cy + radius + 125, "#{total} of #{set.shots.size} shots scored #{set.miss_ring} or worse", 26, t.muted, anchor: "middle")
      [ 1, 0.66, 0.33 ].each do |f|
        parts << %(<circle cx="#{cx}" cy="#{cy}" r="#{(radius * f).round(1)}" fill="none" stroke="#{t.text}" stroke-opacity="0.12" stroke-width="2"/>)
      end
      parts << %(<path d="M#{cx - radius} #{cy}H#{cx + radius}M#{cx} #{cy - radius}V#{cy + radius}" stroke="#{t.text}" stroke-opacity="0.12" stroke-width="2"/>)
      { "HIGH" => [ 0, -1 ], "LOW" => [ 0, 1 ], "LEFT" => [ -1, 0 ], "RIGHT" => [ 1, 0 ] }.each do |word, (dx, dy)|
        parts << eyebrow(cx + dx * (radius + 70), cy + dy * (radius + 70) + 9, word, 22, t.muted, anchor: (dx.zero? ? "middle" : dx.positive? ? "start" : "end"))
      end

      if total < MISS_MIN
        parts << text(cx, cy + 12, total.zero? ? "No misses" : "Too few misses", 40, t.text, weight: 700, anchor: "middle")
        parts << text(cx, cy + 58, "to show a lean", 30, t.sub, anchor: "middle")
        return parts.join
      end

      top = counts.max.to_f
      counts.each_with_index do |count, i|
        next if count.zero?

        r = radius * Math.sqrt(count / top)
        a0, a1 = (i * 45 - 22.5) * Math::PI / 180, (i * 45 + 22.5) * Math::PI / 180
        # y up on the target, down in SVG.
        p0 = [ cx + r * Math.cos(a0), cy - r * Math.sin(a0) ]
        p1 = [ cx + r * Math.cos(a1), cy - r * Math.sin(a1) ]
        parts << %(<path d="M#{cx} #{cy}L#{p0.map { it.round(1) }.join(' ')}A#{r.round(1)} #{r.round(1)} 0 0 0 #{p1.map { it.round(1) }.join(' ')}Z" fill="#{t.highlight}" fill-opacity="0.85" stroke="#{t.bg2}" stroke-width="4"/>)
        mid = i * 45 * Math::PI / 180
        lr = [ r + 34, 70 ].max
        parts << text(cx + lr * Math.cos(mid), cy - lr * Math.sin(mid) + 14, count, 38, t.text, weight: 800, anchor: "middle")
      end
      parts.join
    end
end
