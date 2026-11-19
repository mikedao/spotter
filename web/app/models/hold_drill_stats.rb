# The Journal's hold drill section: how much you have held, and how steady.
# Only drills that held something count; the period filter applies, the gun and
# pellet filters don't (a hold drill has neither).
class HoldDrillStats
  Point = ::Data.define(:label, :y, :title, :filled)

  def initialize(user, days: nil)
    @drills = user.hold_drills.since(days).newest_first.to_a.reverse   # oldest first, as the charts run
  end

  attr_reader :drills

  def any? = drills.any?
  def holds_done = drills.sum(&:reps_done)
  def held_seconds = drills.sum(&:held_seconds)
  def let_downs = drills.sum(&:let_downs)
  def steadiness = drills.sum(&:holds).then { |all| all.zero? ? nil : (100.0 * holds_done / all).round }

  # The longest hold you completed in a full run of the drill (a rep count you finished).
  def longest_hold = drills.select(&:finished?).filter_map { it.hold_seconds if it.let_downs.zero? }.max

  def tiles
    [ [ "Drills", drills.size.to_s, "#{holds_done} holds held" ],
      [ "Time held", format_minutes(held_seconds), "in total" ],
      [ "Steadiness", steadiness ? "#{steadiness}%" : "-", "holds not let down" ],
      [ "Longest clean run", longest_hold ? "#{longest_hold} s" : "-", "every hold held" ] ]
  end

  # One dot per drill: the share of its holds held to the end.
  def points
    drills.map do |d|
      Point.new(d.performed_at.strftime("%b %-d"), d.completion,
                "#{d.performed_at.strftime('%b %-d, %H:%M')}: #{d.summary}", d.plan_ref.present?)
    end
  end

  def newest_first = drills.reverse

  private
    def format_minutes(seconds) = seconds < 90 ? "#{seconds.round} s" : "#{(seconds / 60.0).round(1)} min"
end
