# The first picture of a post: every competition shot of the set on one target,
# framed on the group as the range screen frames it, and fl-shooters' score band
# under it (target_share_controller.js#drawBand, drawn here as SVG): left, the
# accent bar and the total as a poster number ("/600" and the inner tens smaller),
# the event behind a ring glyph, the date, and the series as chips (the best in the
# accent); right, the shooter, their gun and pellets, the group, and Spotter's mark.
class SharePicture::Hero < SharePicture
  U = W / 600.0   # the band's unit, as fl-shooters' at 600 px wide

  private
    def draw
      band, band_h = band(W)
      [ target(0, 0, W, set.shots) + band, W + band_h ]
    end

    def u(n) = n * U

    def band(top)
      pad, gap = u(16), u(7)
      x0 = pad + u(15)
      left_w = W * 0.6 - x0

      score_h = u(78) * 0.74
      sub_h = u(16) * 0.74
      date_h = u(12) * 0.74
      eyebrow_h = u(9) * 0.74
      chips = chip_rows(left_w)
      left_h = score_h + u(14) + sub_h + u(8) + date_h + gap + eyebrow_h + u(3) + chips[:h]

      right = right_rows
      right_h = right.sum { it[:h] } + gap * [ right.size - 1, 0 ].max
      band_h = [ left_h, right_h ].max + 2 * pad

      parts = [ rect(0, top, W, band_h, t.bg2, opacity: 0.96), rect(0, top, W, u(3), t.accent) ]

      # Left, top down: the accent bar and the score, lifted by a glow in the accent.
      y = top + pad + u(4)
      parts << rect(pad, y, u(5), score_h, t.accent, rx: u(2))
      main, rest = set.score_parts
      parts << %(<defs><filter id="lift" x="-20%" y="-40%" width="140%" height="180%"><feGaussianBlur stdDeviation="#{u(5).round(1)}"/></filter></defs>)
      parts << %(<g filter="url(#lift)" opacity="0.75">#{text(x0, y + score_h, main, u(78), t.glow, weight: 800, spacing: -u(2))}</g>)
      parts << text(x0, y + score_h, main, u(78), t.text, weight: 800, spacing: -u(2))
      x = x0 + tw(main, u(78)) * 0.97 + u(4)
      if set.out_of
        parts << text(x, y + score_h, "/#{set.out_of}", u(40), t.text, weight: 700, opacity: 0.55, spacing: -u(1))
        x += tw("/#{set.out_of}", u(40)) + u(8)
      end
      parts << text(x, y + score_h, rest, u(40), t.star, weight: 700, spacing: -u(1)) if rest
      y += score_h + u(14)

      # The event behind a ring glyph, then the date.
      glyph_r = sub_h * 0.55
      parts << glyph(x0 + glyph_r, y + sub_h * 0.55, glyph_r)
      title_size = ShareSvg.fit_size(set.title, u(16), left_w - glyph_r * 2 - u(6), u(10))
      parts << text(x0 + glyph_r * 2 + u(6), y + sub_h, set.title, title_size, t.text, weight: 600, opacity: 0.92)
      y += sub_h + u(8)
      meta = [ set.date_text, set.meta ].join("  ·  ")
      parts << text(x0, y + date_h, meta, ShareSvg.fit_size(meta, u(12), left_w, u(8)), t.text, opacity: 0.65)
      y += date_h + gap

      parts << eyebrow(x0, y + eyebrow_h, chips[:label], u(9), t.text, opacity: 0.65)
      y += eyebrow_h + u(3)
      parts << chips[:svg].call(x0, y)

      # Right, bottom up.
      bottom = top + band_h - pad
      right.reverse_each do |row|
        parts << row[:draw].call(bottom)
        bottom -= row[:h] + gap
      end
      [ parts.join, band_h ]
    end

    # The series totals as chips (the best one in the accent, an unfinished one
    # faint), or each shot's value when there's no complete series yet. Rows wrap
    # rather than run into the right column.
    def chip_rows(max_w)
      h, pad_x, gap, font = u(24), u(6.5), u(4), u(14)
      series = set.series.size > 1 || set.series.first&.complete
      items = series ? set.series : set.shots
      label = series ? "Series" : "Shots"
      texts = items.map { series ? set.number_text(it.total) : set.value_text(it) }
      w = (texts + [ set.whole_rings? ? "100" : "10.9" ]).map { tw(it, font) }.max + 2 * pad_x
      per_row = [ ((max_w + gap) / (w + gap)).floor, 1 ].max
      rows = (items.size / per_row.to_f).ceil
      draw = lambda do |x0, y0|
        items.each_with_index.map do |item, i|
          x = x0 + (i % per_row) * (w + gap)
          y = y0 + (i / per_row) * (h + gap)
          next shot_chip(item, x, y, w, h, font) unless series

          best = item == set.best_series
          fill, ink, opacity = best ? [ t.accent, t.on_accent, nil ] : item.complete ? [ t.text, t.bg2, 0.94 ] : [ t.text, t.text, 0.18 ]
          rect(x, y, w, h, fill, rx: u(4), opacity:) +
            text(x + w / 2.0, y + h / 2.0 + font * 0.36, texts[i], font, ink, weight: 700, anchor: "middle")
        end.join
      end
      { label:, h: rows * h + (rows - 1) * gap, svg: draw }
    end

    # The right column's rows, top to bottom: the shooter, gun, pellets, group, Spotter.
    # Each row's text shrinks to fit the column rather than being cut.
    def right_rows
      right_w = W * 0.36
      rows = []
      if identity?
        name = set.session.user.display_name
        size = ShareSvg.fit_size(name, u(20), right_w, u(12))
        rows << { h: size * 0.74, draw: ->(b) { text(W - u(16), b, name, size, t.text, weight: 700, anchor: "end") } }
        (set.guns + set.pellets).each do |line|
          s = ShareSvg.fit_size(line, u(12), right_w, u(8))
          rows << { h: s * 0.74, draw: ->(b) { text(W - u(16), b, line, s, t.text, anchor: "end", opacity: 0.7) } }
        end
      end
      if (group = set.group_mm)
        value = "#{group} mm"
        rows << { h: u(12) * 0.74, draw: lambda { |b|
          text(W - u(16), b, value, u(12), t.text, weight: 600, anchor: "end") +
            eyebrow(W - u(16) - tw(value, u(12)) - u(7), b, "Group", u(9), t.star, anchor: "end")
        } }
      end
      rows << { h: u(24), draw: ->(b) { ShareSvg.brand(W - u(16), b - u(12), u(24), t) } }
      rows
    end

    # Three rings in the shot colour: the band's nod to the target above it.
    def glyph(cx, cy, r)
      c = shot_colour
      [ 1, 0.62 ].map { %(<circle cx="#{cx.round(2)}" cy="#{cy.round(2)}" r="#{(r * it).round(2)}" fill="none" stroke="#{c}" stroke-width="#{(r * 0.2).round(2)}"/>) }.join +
        %(<circle cx="#{cx.round(2)}" cy="#{cy.round(2)}" r="#{(r * 0.2).round(2)}" fill="#{c}"/>)
    end
end
