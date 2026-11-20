# The Journal's slow dry fire section: shots fired in time, how often you had to let
# one down, and how long a shot takes you to break. Period filter applies, gun and
# pellet filters don't (Pardini dry fire).
class SlowDrillStats
  Point = ::Data.define(:label, :y, :title, :filled)

  def initialize(user, days: nil)
    @drills = user.slow_drills.since(days).newest_first.to_a.reverse   # oldest first, as the charts run
  end

  attr_reader :drills

  def any? = drills.any?
  def shots_fired = drills.sum(&:shots_fired)
  def let_downs = drills.sum(&:let_downs)
  def first_time_rate = (shots_fired + let_downs).then { |all| all.zero? ? nil : (100.0 * shots_fired / all).round }
  def mean_break_seconds = shots_fired.zero? ? nil : (drills.sum(&:break_seconds) / shots_fired).round(1)

  def tiles
    [ [ "Runs", drills.size.to_s, "of the timer" ],
      [ "Shots", shots_fired.to_s, "fired in time" ],
      [ "First time", first_time_rate ? "#{first_time_rate}%" : "-", "raises that became a shot" ],
      [ "Time to break", mean_break_seconds ? "#{mean_break_seconds} s" : "-", "average, from the hold start" ] ]
  end

  # One dot per run: the share of its raises that became a shot (the rest were let down).
  def points
    drills.filter_map do |d|
      next unless d.first_time_rate

      Point.new(d.performed_at.strftime("%b %-d"), d.first_time_rate,
                "#{d.performed_at.strftime('%b %-d, %H:%M')}: #{d.summary}", d.plan_ref.present?)
    end
  end
end
