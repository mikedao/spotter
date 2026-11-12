# A match or final's score, as ISSF counts it: competition shots only (sighters
# never count), a shot out of time scores zero, and a pistol match adds up whole
# rings while finals and rifle add decimals. Series totals: every 10 shots in a
# match, each timed window in a final.
#
#   stats = EventStats.new(session)
#   stats.total          # => 553 (pistol match) or 236.4 (final)
#   stats.fired          # => 57 of stats.course.shots
#   stats.series         # => [ [1, 92], [2, 95], ... ]
class EventStats
  attr_reader :course

  def initialize(session)
    @session = session
    @course = Course.for(session)
    @shots = session.shots.select { it.scored? && it.stage == "match" }.sort_by { it.match_number || 0 }
  end

  def any? = @shots.any?
  def fired = @shots.size
  def sighters = @session.shots.count { it.scored? && it.stage == "sighter" }
  def penalties = @shots.count(&:penalized?)
  def whole_rings? = course.whole_rings?(@session.target)

  def total = sum(@shots)

  def series
    @shots.group_by(&:series).sort_by { |n, _| n.to_i }.map { |n, shots| [ n, sum(shots) ] }
  end

  def value(shot) = shot.penalized? ? 0 : (whole_rings? ? shot.final_ring : shot.final_decimal)

  private
    def sum(shots)
      total = shots.sum { value(it) }
      whole_rings? ? total.to_i : total.round(1)
    end
end
