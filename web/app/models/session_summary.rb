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

  def tens = rings.count(10)
  def tens_per_60 = charted? ? (tens * 60.0 / count).round(1) : nil
  def inner_tens = shots.count { !it.penalized? && it.final_inner_ten? }

  # Mean of each card's group size (centre to centre), so a card change mid-
  # session doesn't count as one huge group.
  def group_mm
    sizes = session.cards.filter_map { |card| CardStats.new(card.shots.select { it.scored? && !it.sighter? }, session.target_spec).group_size_mm }
    sizes.any? ? (sizes.sum / sizes.size).round(1) : nil
  end

  def decimal_average = count.positive? ? (shots.sum { it.penalized? ? 0 : it.final_decimal.to_f } / count).round(2) : nil
end
