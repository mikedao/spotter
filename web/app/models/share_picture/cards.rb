# Each card of the set as its own small target with its score, in order, all at
# one zoom (the widest any card needs) so the groups compare at a glance. Past
# MAX_CARDS the last cell says "+ N more cards" rather than shrinking them away.
class SharePicture::Cards < SharePicture
  MAX_CARDS = 24
  FOOTER = 260
  LABEL_H = 92
  GAP = 36

  private
    def draw
      head, y0 = header("Every card")
      cards = set.cards
      shown = cards.size > MAX_CARDS ? cards.first(MAX_CARDS - 1) : cards
      cells = shown.size + (cards.size > shown.size ? 1 : 0)
      cols = case cells
      when 1 then 1
      when 2..4 then 2
      when 5..9 then 3
      else 4
      end
      size = [ (W - 2 * MARGIN - GAP * (cols - 1)) / cols.to_f, 900 ].min
      left = (W - cols * size - (cols - 1) * GAP) / 2.0
      rows = (cells / cols.to_f).ceil
      top = y0 + 40
      height = [ (top + rows * (size + LABEL_H + GAP) + FOOTER).ceil, 1200 ].max
      ring = shown.map { view_ring(it.shots) }.min

      parts = [ head ]
      shown.each_with_index do |card, i|
        x = left + (i % cols) * (size + GAP)
        y = top + (i / cols) * (size + LABEL_H + GAP)
        parts << rect(x - 6, y - 6, size + 12, size + 12, t.edge, rx: 10, opacity: t.edge_op)
        parts << target(x, y, size, card.shots, ring:, numbers: cols <= 3)
        parts << card_label(card, x, y + size, size)
      end
      if cells > shown.size
        i = shown.size
        x = left + (i % cols) * (size + GAP)
        y = top + (i / cols) * (size + LABEL_H + GAP)
        parts << rect(x, y, size, size, t.row, rx: 10, opacity: t.row_op, stroke: t.edge, stroke_width: 2, stroke_opacity: t.edge_op)
        more = "+ #{cards.size - shown.size} more"
        parts << text(x + size / 2.0, y + size / 2.0 + 20, more, ShareSvg.fit_size(more, 64, size - 40, 24), t.text, weight: 800, anchor: "middle")
      end
      parts << footer(height)
      [ parts.join, height ]
    end

    def card_label(card, x, y, size)
      total = set.number_text(set.card_total(card))
      x_count = set.card_inner_tens(card)
      score = set.whole_rings? && x_count.positive? ? "#{total}-#{x_count}x" : total
      score_size = ShareSvg.fit_size(score, 54, size * 0.5, 26)
      label_size = ShareSvg.fit_size(card.label, 34, size - tw(score, score_size) - 24, 18)
      base = y + 64
      [ text(x, base, card.label, label_size, t.sub, weight: 600),
        text(x + size, base, score, score_size, t.text, weight: 800, anchor: "end") ].join
    end
end
