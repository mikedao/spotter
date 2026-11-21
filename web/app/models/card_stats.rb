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

  # whole_rings: true when the session is scored in whole rings (pistol), so the
  # score and average shown are rings - a "78 (81.8)" mixes two scores.
  def initialize(shots, spec, whole_rings: false)
    @shots = shots.select { |s| s.final_x_mm && s.final_y_mm }
    @spec = spec
    @whole_rings = whole_rings
  end

  def whole_rings? = @whole_rings

  # The card's score and average per shot, as the session is scored.
  def score = whole_rings? ? total : decimal_total
  def score_average = any? ? (whole_rings? ? (total.to_f / count).round(2) : average) : nil

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

  # The two shots farthest apart: the pair the group size is measured between.
  def widest_pair
    return nil if count < 2

    shots.combination(2).max_by { |a, b| Math.hypot(a.final_x_mm - b.final_x_mm, a.final_y_mm - b.final_y_mm) }
  end

  # One run of `of` shots in firing order: its number on the card, its shots, its
  # size (nil below two shots) and whether all `of` are in.
  Group = Data.define(:number, :shots, :size_mm, :complete) do
    def range_text = shots.size == 1 ? "shot #{shots.first.number}" : "shots #{shots.first.number}–#{shots.last.number}"
  end

  # The card in runs of `of` shots in firing order (a 10-shot card as two 5-shot
  # groups, shot without changing the card). Sighters are never part of a group.
  def groups(of:)
    shots.reject(&:sighter?).sort_by(&:fired_at).each_slice(of).with_index(1).map do |run, number|
      Group.new(number, run, self.class.new(run, spec).group_size_mm, run.size == of)
    end
  end

  # The group being shot: the last run (a finished one stays current until the next shot).
  def current_group(of:) = groups(of:).last

  # Group sizes of each run of `of` shots. Only a run of at least two shots counts,
  # so a group still being shot shows as soon as it has a pair.
  def group_sizes(of:) = groups(of:).filter_map(&:size_mm)

  # Seconds between consecutive shots on the card.
  def intervals_s = shots.sort_by(&:fired_at).each_cons(2).map { |a, b| (b.fired_at - a.fired_at).round }
  def average_interval_s = intervals_s.any? ? (intervals_s.sum / intervals_s.size.to_f).round : nil

  # How the engine found the shots - "7 heard · 2 seen · 1 seen/heard" - so the
  # shooter can see how well the sound trigger works against the camera alone.
  def found_by = shots.group_by(&:found_by).transform_values(&:size)
  def found_by_text = %w[ heard seen seen/heard ].filter_map { |k| "#{found_by[k]} #{k}" if found_by[k] }.join(" · ").presence

  # Seconds from the sound to the score, the middle of the shots that have one
  # (heard and seen/heard): a slowdown over a session shows here.
  def median_detect_s
    times = shots.filter_map(&:detect_seconds).sort
    return nil if times.empty?

    mid = times.size / 2
    (times.size.odd? ? times[mid] : (times[mid - 1] + times[mid]) / 2.0).round(1)
  end
end
