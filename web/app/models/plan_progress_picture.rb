# The whole training plan as one picture, for a plan day's post (PlanDayShare):
# a row per calendar week, a cell per day - done filled in the accent, missed
# faint, still to come outlined, this post's day ringed - each marked with its
# kind (A air pistol, D dry fire + air pistol, R range day, M match day, rest
# days blank). The footer: days done of the plan and the current run of days done.
class PlanProgressPicture < SharePicture
  CELL_H = 64
  GAP = 12
  LABEL_W = 110
  FOOTER = 260

  def initialize(share, colors: nil, identity: true) = super(share, colors:, identity:)

  def filename = "spotter-plan-progress.jpg"

  private
    def share = set
    def enrollment = share.enrollment

    def draw
      width = W - 2 * MARGIN
      parts = [ eyebrow(MARGIN, 170, "Training plan", 40, t.accent) ]
      lines, size = ShareSvg.lines_for(TrainingPlan.name, 84, width, 2, 52)
      y = 170 + 40 + size
      lines.each { parts << text(MARGIN, y, it, size, t.text, weight: 800); y += (size * 1.12).round }
      sub = [ (share.user.display_name if identity?), share.date_text, "#{share.heading}: #{share.day.title}" ].compact.join("  ·  ")
      sub_lines, sub_size = ShareSvg.lines_for(sub, 40, width, 2, 28)
      y += 4
      sub_lines.each { parts << text(MARGIN, y, it, sub_size, t.sub); y += (sub_size * 1.3).round }

      y += 50
      cell_w = (width - LABEL_W - GAP * 6) / 7.0
      enrollment.calendar.each_with_index do |days, week|
        parts << text(MARGIN, y + CELL_H / 2.0 + 12, "W#{week + 1}", 32, t.muted, weight: 700)
        days.each_with_index do |day, i|
          parts << cell(day, MARGIN + LABEL_W + i * (cell_w + GAP), y, cell_w)
        end
        y += CELL_H + GAP
      end
      y += 20
      parts << legend(y)
      height = y + 60 + FOOTER
      parts << footer_progress(height)
      [ parts.join, height ]
    end

    def pause?(day) = day.respond_to?(:pause?)
    def done?(day) = !pause?(day) && enrollment.done?(day.week, day.day)
    def this?(day) = !pause?(day) && day.week == share.day.week && day.day == share.day.day
    def missed?(day) = !pause?(day) && !done?(day) && enrollment.date_of(day.ref) < Time.zone.today

    def mark(day)
      return "" if pause?(day) || day.rest?
      return "M" if day.match?
      return "R" if day.range?

      day.dry? ? "D" : "A"
    end

    def cell(day, x, y, w)
      parts = []
      if done?(day)
        parts << rect(x, y, w, CELL_H, t.accent, rx: 10)
      elsif missed?(day)
        parts << rect(x, y, w, CELL_H, t.text, rx: 10, opacity: 0.12)
      else
        parts << rect(x, y, w, CELL_H, t.row, rx: 10, opacity: t.row_op, stroke: t.edge, stroke_width: 2, stroke_opacity: t.edge_op)
      end
      parts << rect(x - 5, y - 5, w + 10, CELL_H + 10, "none", rx: 14, stroke: t.text, stroke_width: 5) if this?(day)
      label = mark(day)
      ink = done?(day) ? t.on_accent : t.sub
      parts << text(x + w / 2.0, y + CELL_H / 2.0 + 11, label, 30, ink, weight: 800, anchor: "middle") if label.present?
      parts.join
    end

    def legend(y)
      items = [ [ "A", "air pistol" ], [ "D", "dry fire + air pistol" ], [ "R", "range day" ], [ "M", "match" ] ]
      x = MARGIN
      items.map do |key, what|
        part = text(x, y + 30, "#{key} #{what}", 28, t.muted, weight: 600)
        x += tw("#{key} #{what}", 28) + 44
        part
      end.join
    end

    # Days done in a row, back from this post's day (calendar order; added rest
    # days neither break nor extend it).
    def streak
      order = enrollment.calendar.flatten
      at = order.index { this?(it) } or return 0
      order[0..at].reverse.reject { pause?(it) }.take_while { done?(it) }.size
    end

    def footer_progress(bottom)
      y = bottom - 90
      done = share.done_count.to_s
      parts = [ eyebrow(MARGIN, y - 92, "Days done", 28, t.muted) ]
      parts << text(MARGIN, y, done, 96, t.text, weight: 800)
      x = MARGIN + tw(done, 96) + 10
      parts << text(x, y, "/#{share.workout_count}", 52, t.text, weight: 700, opacity: 0.55)
      run = streak
      parts << text(x + tw("/#{share.workout_count}", 52) + 30, y, "#{run} in a row", 44, t.star, weight: 700) if run > 1
      label = "Logged with Spotter"
      size = 64
      right = W - MARGIN
      mid = y - 30
      parts << text(right, mid + size * 0.21, label, size * 0.6, t.text, weight: 600, anchor: "end", opacity: 0.9)
      parts << ShareSvg.mark(right - tw(label, size * 0.6) - size * 0.35 - size, mid - size / 2.0, size)
      parts.join
    end
end
