# The range screen's match / final panel: what the range officer last called,
# the time left in the current window (counted down in the browser from the
# engine's ends_at, by countdown_controller.js), "Start match" during a match's
# sighting time, and the event's score (EventStats) with its series. Replaced on
# every engine event (LiveBroadcast). Practice sessions have none.
class CoursePanelComponent < ApplicationComponent
  def initialize(session:) = @session = session

  def render? = @session.course.present?

  def course = @session.course_info
  def state = @session.course_state || {}
  def stats = @stats ||= EventStats.new(@session)
  def live? = @session.live?

  def heading
    return "Results are final" if state["phase"] == "done" || !live?

    case state["phase"]
    when "window"
      if state["stage"] == "sighting" then "Sighting time left"
      elsif state["label"] == course.name then "Time left"
      else state["label"]
      end
    when "command" then state["label"].to_s.upcase_first
    when "pause" then "Wait"
    else "Waiting for the range officer"
    end
  end

  def counting? = live? && state["ends_at"].present? && %w[ window pause ].include?(state["phase"])
  def skippable? = live? && state["phase"] == "window" && state["skippable"]

  # When the clock turns amber and red: the last 10 / 1 minutes of a match,
  # the last 15 / 5 seconds of a final's window.
  def warn_at = course&.key == "match" && state["stage"] == "match" ? [ 600, 60 ] : [ 15, 5 ]

  def total_text
    return "–" unless stats.any?

    stats.whole_rings? ? stats.total.to_s : format("%.1f", stats.total)
  end
end
