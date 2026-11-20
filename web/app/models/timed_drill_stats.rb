# The Journal's timed fire section: how many strings of dry fire against the clock
# you have done, and how fast. Like the hold drills, the period filter applies and
# the gun / pellet filters don't (it is Pardini dry fire).
class TimedDrillStats
  Point = ::Data.define(:label, :y, :title, :filled)

  def initialize(user, days: nil)
    @drills = user.timed_drills.since(days).newest_first.to_a.reverse   # oldest first, as the charts run
  end

  attr_reader :drills

  def any? = drills.any?
  def strings_done = drills.sum(&:strings_done)
  def shots = drills.sum { it.strings_done * it.shots }

  # The shortest time a string was shot in, from a run you finished.
  def fastest = drills.select(&:finished?).map(&:string_seconds).min

  def tiles
    [ [ "Runs", drills.size.to_s, "of the timer" ],
      [ "Strings", strings_done.to_s, "to the stop beep" ],
      [ "Shots", shots.to_s, "dry, in time" ],
      [ "Fastest string", fastest ? "#{fastest} s" : "-", "in a full run" ] ]
  end

  # One dot per run: the share of its strings shot to the stop beep.
  def points
    drills.map do |d|
      Point.new(d.performed_at.strftime("%b %-d"), (100.0 * d.strings_done / d.strings).round,
                "#{d.performed_at.strftime('%b %-d, %H:%M')}: #{d.summary}", d.plan_ref.present?)
    end
  end
end
