# A finished session as a whole (the session page once it has ended): the result
# - total, series, 10s, the session's group - and every card, each linking to its
# own page. Counted as the rules count: competition shots only (sighters never
# count), out-of-time shots score 0, whole rings for pistol practice and matches,
# decimals for rifle and finals; your calls win.
class SessionResultComponent < ApplicationComponent
  def initialize(session:) = @session = session

  private
    attr_reader :session

    def course = session.course_info
    def event = @event ||= course && EventStats.new(session)
    def summary = @summary ||= SessionSummary.new(session)
    def shots = summary.shots
    def stats = @stats ||= CardStats.new(shots.reject(&:penalized?), session.target_spec, whole_rings: session.whole_rings?)
    def sighters = session.shots.count { it.scored? && it.sighter? }

    def title = course ? "#{course.name} result" : "Session result"

    def total
      return event.whole_rings? ? event.total : format("%.1f", event.total) if event
      session.whole_rings? ? summary.total : format("%.1f", shots.sum { it.penalized? ? 0 : it.final_decimal.to_f })
    end

    def out_of = event ? "of #{course.shots} shots" : nil

    # [ label, total ] per series: a match's 10s and a final's windows (EventStats),
    # or 10-shot series in practice.
    def series
      if event then event.series.map { |n, t| [ "S#{n}", event.whole_rings? ? t : format("%.1f", t) ] }
      else summary.series.each_with_index.map { |t, i| [ "S#{i + 1}", t ] }
      end
    end

    def worst = series.map(&:last).min_by(&:to_f)

    def figures
      [ [ "Shots", shots.size ],
        [ "Average", stats.score_average || "–" ],
        (session.whole_rings? && !event ? [ "Per 60", summary.per_60 || "–" ] : nil),
        [ "10s", summary.tens ],
        [ "Inner tens", stats.inner_tens ],
        [ "Group", stats.group_size_mm ? "#{stats.group_size_mm} mm" : "–" ],
        [ "Group center", stats.count >= 2 ? "#{stats.mean_point_offset_mm} mm #{stats.mean_point_direction}" : "–" ],
        [ "Mean radius", stats.mean_radius_mm ? "#{stats.mean_radius_mm} mm" : "–" ],
        [ "Time per shot", stats.average_interval_s ? "#{stats.average_interval_s} s" : "–" ],
        [ "Found", stats.found_by_text || "–" ],
        [ "Sound to score", stats.median_detect_s ? "#{stats.median_detect_s} s" : "–" ] ].compact
    end
end
