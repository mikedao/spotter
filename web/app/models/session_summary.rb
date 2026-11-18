# One session's numbers for the journal, aimed at what pistol qualification is
# decided on: 60 shots in WHOLE rings. Competition shots only (sighters never
# count, a shot out of time scores 0), each shot's FINAL ring (your call wins).
#
#   s = SessionSummary.new(session)
#   s.per_60          # => 571   score scaled to 60 shots (a match: its real pace)
#   s.series          # => [ 96, 94, 97 ]   complete 10-shot series, in order
#   s.tens_per_60     # => 21.4
#   s.group_mm        # => 31.2  mean group size over its cards
class SessionSummary
  SERIES = 10
  MIN_SHOTS = 10    # fewer is too noisy to put on the trend

  attr_reader :session

  delegate :started_at, :gun, :pellet, :exercises, :problems, :fixes, :learned, to: :session

  def initialize(session)
    @session = session
  end

  def kind
    case session.course
    when nil then "practice"
    when "match" then "match"
    else "final"
    end
  end

  def shots
    @shots ||= session.cards.flat_map(&:shots).select { it.scored? && !it.sighter? }.sort_by(&:fired_at)
  end

  def count = shots.size
  def charted? = count >= MIN_SHOTS
  def rings = @rings ||= shots.map { it.penalized? ? 0 : it.final_ring.to_i }
  def total = rings.sum
  def per_60 = charted? ? (total * 60.0 / count).round : nil

  def series = rings.each_slice(SERIES).select { it.size == SERIES }.map(&:sum)
  def worst_series = series.min
  def best_series = series.max
  def mean_series = series.any? ? (series.sum.to_f / series.size).round(1) : nil

  # Where the shots landed, by ring: "X" (inner ten), "10" (the rest of the ten),
  # "9", "8", "7", "≤6" (a penalized shot scores 0, so it lands there).
  LANDING = [ "X", "10", "9", "8", "7", "≤6" ].freeze

  def self.landing_key(shot, ring)
    if ring == 10 then (shot.final_inner_ten? ? "X" : "10")
    elsif ring >= 7 then ring.to_s
    else "≤6"
    end
  end

  def landing
    shots.zip(rings).each_with_object(LANDING.index_with(0)) { |(shot, ring), counts| counts[self.class.landing_key(shot, ring)] += 1 }
  end

  # Seconds since the shot before, with where it landed: [ [ 22.4, "9" ], ... ].
  # Only between two shots on the SAME card (a card change is 96 s or more), and
  # only up to MAX_GAP_S (a pause or a break); penalized shots left out (their
  # time is the range officer's). A shot found by the camera is timed when SEEN,
  # ~1-2 s late, so a gap is good to a couple of seconds.
  MAX_GAP_S = 90

  def rhythm
    shots.each_cons(2).filter_map do |before, shot|
      next if shot.penalized? || before.card_id != shot.card_id

      gap = shot.fired_at - before.fired_at
      [ gap.round(1), self.class.landing_key(shot, shot.final_ring.to_i) ] if gap.between?(0, MAX_GAP_S)
    end
  end

  # The MISSES (an 8 or worse; penalized shots left out - their ring isn't where
  # they went) by direction from the centre, TargetSpec::DIRECTIONS as the
  # announcer says them.
  MISS_BELOW = 9

  def misses
    shots.zip(rings).each_with_object(TargetSpec::DIRECTIONS.index_with(0)) do |(shot, ring), counts|
      next if shot.penalized? || ring >= MISS_BELOW || !shot.final_x_mm

      dir = TargetSpec.direction(shot.final_x_mm, shot.final_y_mm)
      counts[dir] += 1 if counts.key?(dir)
    end
  end

  def tens = rings.count(10)
  def tens_per_60 = charted? ? (tens * 60.0 / count).round(1) : nil
  def inner_tens = shots.count { !it.penalized? && it.final_inner_ten? }

  # Mean of each card's group size (centre to centre), so a card change mid-
  # session doesn't count as one huge group.
  def group_mm
    sizes = session.cards.filter_map { |card| CardStats.new(card.shots.select { it.scored? && !it.sighter? }, session.target_spec).group_size_mm }
    sizes.any? ? (sizes.sum / sizes.size).round(1) : nil
  end

  # Where the group sits: the mean of every shot's position (mm, y up), and in
  # words ("4.2 mm low left"), for the group chart's hover.
  def group_centre
    pts = shots.filter_map { [ it.final_x_mm, it.final_y_mm ] if it.final_x_mm && it.final_y_mm }
    return if pts.empty?

    x, y = pts.sum(&:first) / pts.size, pts.sum(&:last) / pts.size
    "#{Math.hypot(x, y).round(1)} mm #{TargetSpec.direction(x, y)}".sub(" mm center", " mm, centred")
  end

  def decimal_average = count.positive? ? (shots.sum { it.penalized? ? 0 : it.final_decimal.to_f } / count).round(2) : nil
end
