# Every series of the set as a row of shot chips with its total, like a paper
# scorecard: an inner ten in the accent, the best series' total in the accent and
# the worst outlined; a day of training heads each session's rows with when it was.
# Rows get smaller as there are more of them, then the picture grows - no series is
# ever left off.
class SharePicture::Scorecard < SharePicture
  HEIGHT = 2000
  FOOTER = 260
  LABEL_W = 130
  TOTAL_W = 250

  private
    def draw
      head, y0 = header("Scorecard")
      rows = layout
      units = rows.sum { it[:units] }
      room = HEIGHT - FOOTER - (y0 + 40)
      row_h = (room / [ units, 1 ].max).clamp(64, 150)
      height = [ HEIGHT, (y0 + 40 + units * row_h + FOOTER).ceil ].max

      y = y0 + 40
      parts = [ head ]
      rows.each do |row|
        h = row[:units] * row_h
        parts << (row[:heading] ? heading(row[:heading], y, h) : series_row(row[:series], y, row_h))
        y += h
      end
      parts << footer(height)
      [ parts.join, height ]
    end

    # The rows: each series, after a heading line per session when there are several.
    def layout
      set.series.chunk_while { |a, b| a.session == b.session }.flat_map do |group|
        s = group.first.session
        heading = "#{s.started_at.strftime('%b %-d · %H:%M')} · #{s.course_info&.name || 'Practice'}" unless set.single?
        [ ({ heading:, units: 0.62 } if heading), *group.map { { series: it, units: 1 } } ].compact
      end
    end

    def heading(label, y, h) = eyebrow(MARGIN, y + h * 0.72, label, [ h * 0.4, 30 ].min, t.star)

    def series_row(series, y, row_h)
      h = row_h * 0.8
      top = y + (row_h - h) / 2.0
      best, worst = series == set.best_series, series == set.worst_series
      parts = [ rect(MARGIN - 24, top, W - 2 * MARGIN + 48, h, t.row, rx: h * 0.16, opacity: t.row_op,
                     stroke: (MISS if worst), stroke_width: (4 if worst)) ]
      label_size = (h * 0.4).clamp(24, 46)
      parts << text(MARGIN, top + h / 2.0 + label_size * 0.36, series.label, label_size, t.muted, weight: 700)

      # Ten chips across, or as many as the longest series has (a final's 5-shot windows).
      slots = [ set.series.map { it.shots.size }.max, 1 ].max
      gap = 10
      area = W - 2 * MARGIN - LABEL_W - TOTAL_W
      chip_w = [ (area - gap * (slots - 1)) / slots.to_f, h * 1.6 ].min
      chip_h = h * 0.66
      font = [ chip_h * 0.5, ShareSvg.fit_size(set.whole_rings? ? "10" : "10.9", chip_h * 0.5, chip_w - 12, 14) ].min
      series.shots.each_with_index do |shot, i|
        parts << shot_chip(shot, MARGIN + LABEL_W + i * (chip_w + gap), top + (h - chip_h) / 2.0, chip_w, chip_h, font)
      end

      total = set.number_text(series.total)
      total_size = (h * 0.56).clamp(30, 80)
      colour = best ? t.highlight : t.text
      parts << text(W - MARGIN, top + h / 2.0 + total_size * 0.36, total, total_size, colour, weight: 800, anchor: "end", opacity: (series.complete ? nil : 0.55))
      tag = best ? "Best" : (worst ? "Worst" : (series.complete ? nil : "#{series.shots.size} shots"))
      parts << eyebrow(W - MARGIN - tw(total, total_size) - 16, top + h / 2.0 + 9, tag, 22, best ? t.highlight : t.muted, anchor: "end") if tag
      parts.join
    end
end
