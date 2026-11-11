# The numbers for one card, after freETarget's Session statistics: total and
# decimal total, average, inner tens, the mean point of impact (where the group
# sits - a consistent offset is a sight adjustment, not technique), the mean radius
# about it, the group size, and the time between shots.
#
# Uses each shot's FINAL values, so the shooter's calls count.
#
#   stats = CardStats.new(card.scored_shots, card.practice_session.target_spec)
#   stats.total             # => 87
#   stats.mean_point        # => [ -3.1, 2.4 ] mm, y up
#   stats.group_size_mm     # => 31.6, centre to centre
class CardStats
  attr_reader :shots, :spec

  def initialize(shots, spec)
    @shots = shots.select { |s| s.final_x_mm && s.final_y_mm }
    @spec = spec
  end

  def count = shots.size
  def any? = count.positive?
  def total = shots.sum(&:final_ring)
  def decimal_total = shots.sum(&:final_decimal).round(1)
  def average = any? ? (decimal_total / count).round(2) : nil
  def inner_tens = shots.count(&:final_inner_ten?)

  # Mean point of impact, mm from the centre (x right, y up).
  def mean_point
    return nil unless any?

    [ shots.sum(&:final_x_mm) / count, shots.sum(&:final_y_mm) / count ].map { it.round(1) }
  end

  def mean_point_offset_mm = mean_point && Math.hypot(*mean_point).round(1)
  def mean_point_direction = mean_point && TargetSpec.direction(*mean_point)

  # Average distance of the shots from their own middle: one stray shot can't
  # inflate it the way it does the group size.
  def mean_radius_mm
    return nil if count < 2

    mx, my = mean_point
    (shots.sum { Math.hypot(it.final_x_mm - mx, it.final_y_mm - my) } / count).round(1)
  end

  # Widest distance between two shot centres (freETarget's group size). Add one
  # pellet (4.5 mm) for the edge-to-edge figure fl-shooters shows.
  def group_size_mm
    return nil if count < 2

    shots.combination(2).map { |a, b| Math.hypot(a.final_x_mm - b.final_x_mm, a.final_y_mm - b.final_y_mm) }.max.round(1)
  end

  # Seconds between consecutive shots on the card.
  def intervals_s = shots.sort_by(&:fired_at).each_cons(2).map { |a, b| (b.fired_at - a.fired_at).round }
  def average_interval_s = intervals_s.any? ? (intervals_s.sum / intervals_s.size.to_f).round : nil
end
