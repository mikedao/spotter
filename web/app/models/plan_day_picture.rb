# The picture of a training-plan day posted to CompetitiveShooter.org
# (PlanDayShare): the day's title and focus, a row per block with what was done
# ("10/10", a check when it finished the block), the note, and the plan's
# progress, in the share pictures' colorways. The composer's Look sets the colors,
# the name, a headline of the shooter's own, and whether the note and the progress
# are on it. Nothing on it is cut off: titles shrink and wrap (ShareSvg's house rule).
class PlanDayPicture < SharePicture
  ROW_H = 200
  ROW_GAP = 28

  def initialize(share, colors: nil, look: nil)
    @look = look || share.default_look.then { colors ? it.with(colors: ShareColorway.key_for(colors)) : it }
    super(share, colors: @look.colors, identity: @look.identity)
  end

  def filename = "spotter-plan-day.jpg"

  private
    def share = set

    def draw
      width = W - 2 * MARGIN
      parts = [ eyebrow(MARGIN, 170, "Training plan · #{share.heading}", 40, t.accent) ]

      lines, size = ShareSvg.lines_for(@look.headline || share.day.title, 92, width, 2, 56)
      y = 170 + 40 + size
      lines.each { parts << text(MARGIN, y, it, size, t.text, weight: 800); y += (size * 1.12).round }

      minutes = share.day.minutes
      sub = [ (share.user.display_name if identity?), (share.day.title if @look.headline), share.date_text, share.kind_text, ("#{minutes} min" if minutes.positive?) ].compact.join("  ·  ")
      sub_lines, sub_size = ShareSvg.lines_for(sub, 42, width, 2, 30)
      y += 4
      sub_lines.each { parts << text(MARGIN, y, it, sub_size, t.sub, weight: 500); y += (sub_size * 1.3).round }

      focus_lines, focus_size = ShareSvg.lines_for(share.day.focus, 40, width, 3, 30)
      y += 30
      focus_lines.each { parts << text(MARGIN, y, it, focus_size, t.text, opacity: 0.8); y += (focus_size * 1.35).round }

      y += 50
      share.items.each do |item|
        parts << row(item, y)
        y += ROW_H + ROW_GAP
      end

      if @look.note && share.note.present?
        y += 20
        parts << eyebrow(MARGIN, y, "Note", 28, t.muted)
        note_lines, note_size = ShareSvg.lines_for(share.note, 38, width, 4, 28)
        y += 20
        note_lines.each { y += (note_size * 1.35).round; parts << text(MARGIN, y, it, note_size, t.sub) }
        y += 30
      end

      height = y + 260
      parts << footer_day(height)
      [ parts.join, height ]
    end

    # A block: the check, its name and what it means on the left, the value right.
    def row(item, top)
      x = MARGIN
      w = W - 2 * MARGIN
      cx, cy, radius = x + 80, top + ROW_H / 2.0, 42
      value_size = ShareSvg.fit_size(item.value, 104, 360, 56)
      text_w = w - 160 - ShareSvg.text_width(item.value, value_size) - 80
      name_size = ShareSvg.fit_size(item.name, 56, text_w, 36)
      detail_lines, detail_size = ShareSvg.lines_for(item.detail, 32, text_w, 2, 22)

      parts = [ rect(x, top, w, ROW_H, t.row, rx: 24, opacity: t.row_op, stroke: t.edge, stroke_width: 2, stroke_opacity: t.edge_op) ]
      if item.done
        parts << %(<circle cx="#{cx}" cy="#{cy}" r="#{radius}" fill="#{t.accent}"/>)
        parts << %(<path d="M#{cx - 18} #{cy + 1}l13 13l25 -27" fill="none" stroke="#{t.on_accent}" stroke-width="9" stroke-linecap="round" stroke-linejoin="round"/>)
      else
        parts << %(<circle cx="#{cx}" cy="#{cy}" r="#{radius}" fill="none" stroke="#{t.text}" stroke-opacity="0.35" stroke-width="5"/>)
      end
      tx = x + 160
      block_h = name_size + 14 + detail_lines.size * detail_size * 1.3
      ty = cy - block_h / 2.0 + name_size * 0.85
      parts << text(tx, ty, item.name, name_size, t.text, weight: 800)
      ty += 14
      detail_lines.each { ty += detail_size * 1.3; parts << text(tx, ty - detail_size * 0.3, it, detail_size, t.sub) }
      parts << text(x + w - 50, cy + value_size * 0.36, item.value, value_size, item.done ? t.text : t.muted, weight: 800, anchor: "end")
      parts.join
    end

    # The plan's progress on the left, Spotter's mark on the right.
    def footer_day(bottom)
      y = bottom - 90
      done = share.done_count.to_s
      parts = []
      if @look.progress
        parts << eyebrow(MARGIN, y - 92, "Training plan", 28, t.muted)
        parts << text(MARGIN, y, done, 96, t.text, weight: 800)
        x = MARGIN + tw(done, 96) + 10
        rest = "/#{share.workout_count}"
        parts << text(x, y, rest, 52, t.text, weight: 700, opacity: 0.55)
        parts << text(x + tw(rest, 52) + 14, y, "days done", 40, t.star, weight: 700)
      end
      label = "Logged with Spotter"
      size = 64
      right = W - MARGIN
      mid = y - 30
      label_w = tw(label, size * 0.6)
      parts << text(right, mid + size * 0.21, label, size * 0.6, t.text, weight: 600, anchor: "end", opacity: 0.9)
      parts << ShareSvg.mark(right - label_w - size * 0.35 - size, mid - size / 2.0, size)
      parts.join
    end
end
