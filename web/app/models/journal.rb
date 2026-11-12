# The journal: the shooter's sessions as trends, filtered. Charts read oldest
# first, the list newest first. Filters (all optional, from the query string):
# target (pistol | rifle), kind (practice | match | final), gun, pellet,
# exercise, and how far back (days).
#
#   journal = Journal.new(Current.user, params)
#   journal.charted      # SessionSummary list with >= 10 shots, oldest first
#   journal.goal         # 565 - the goal line, per 60 shots
class Journal
  KINDS = { "practice" => "Practice", "match" => "Match", "final" => "Final" }.freeze
  PERIODS = { "30" => "Last 30 days", "90" => "Last 90 days", "365" => "Last year" }.freeze
  DEFAULT_GOALS = { "pistol" => 565 }.freeze   # the shooter's trials benchmark

  attr_reader :user, :filters

  def initialize(user, params = {})
    @user = user
    @filters = params.to_h.symbolize_keys.slice(:target, :kind, :gun, :pellet, :exercise, :days).compact_blank
    @filters[:target] = target
  end

  # The type you shoot most, unless chosen.
  def target
    @filters&.dig(:target).presence_in(TargetSpec::SPECS.keys) ||
      user.practice_sessions.group(:target).order(Arel.sql("COUNT(*) DESC")).limit(1).pick(:target) || "pistol"
  end

  # The shooter's goal; 565 for pistol until they set one. Removed = no line.
  def goal
    goals = user.goals || {}
    goals.key?(target) ? goals[target]&.to_i : DEFAULT_GOALS[target]
  end
  def series_goal = goal && (goal / 6.0).round(1)    # the pace per 10-shot series

  def summaries
    @summaries ||= scope.includes(:gun, :pellet, :exercises, cards: :shots).order(:started_at).map { SessionSummary.new(it) }
  end

  def charted = @charted ||= summaries.select(&:charted?)

  # The headline tiles. RECENT sessions = the last 5 charted; "before" = the 5
  # before them.
  RECENT = 5
  TREND_SESSIONS = 8     # fewer, or under TREND_DAYS apart, is too noisy to forecast from
  TREND_DAYS = 14

  def recent_pace = pace(charted.last(RECENT))
  def previous_pace = pace(charted[0...-RECENT].to_a.last(RECENT))
  def to_goal = goal && recent_pace && goal - recent_pace         # > 0: still to go
  def closing = recent_pace && previous_pace && recent_pace - previous_pace   # > 0: closer
  def personal_best = charted.max_by { [ it.per_60, -it.started_at.to_i ] }   # a tie: when first set
  def worst_recent_series = charted.last(RECENT).filter_map(&:worst_series).min

  def trend_ready? = charted.size >= TREND_SESSIONS && (charted.last.started_at - charted.first.started_at) >= TREND_DAYS.days

  # Score per 60 gained per 30 days: a least-squares line through the sessions.
  def trend_per_month
    return unless trend_ready?

    (slope_per_day * 30).round(1)
  end

  # When the trend line reaches the goal (nil when there is no goal, it is
  # already reached, or the trend isn't climbing).
  def goal_forecast
    return unless trend_ready? && goal && slope_per_day.positive?

    days = (goal - fitted_now) / slope_per_day
    days.positive? ? charted.last.started_at.to_date + days.ceil : nil
  end
  def newest_first = summaries.reverse
  def with_notes = newest_first.select { [ it.problems, it.fixes, it.learned ].any?(&:present?) }

  # What the filter menus offer: only what the shooter has.
  def guns = user.guns.of_kind(target).by_name
  def pellets = user.pellets.by_name
  def exercises = user.exercises.by_use

  private
    def pace(list) = list.any? ? (list.sum(&:per_60) / list.size.to_f).round : nil

    def days_of(summary) = (summary.started_at - charted.first.started_at) / 1.day

    def fit
      @fit ||= begin
        xs, ys = charted.map { days_of(it) }, charted.map(&:per_60)
        mx, my = xs.sum / xs.size, ys.sum / ys.size.to_f
        slope = xs.zip(ys).sum { |x, y| (x - mx) * (y - my) } / xs.sum { (it - mx)**2 }
        [ slope, my - slope * mx ]
      end
    end

    def slope_per_day = fit.first
    def fitted_now = fit.last + slope_per_day * days_of(charted.last)

    def scope
      sessions = user.practice_sessions.where(target:)
      sessions = case @filters[:kind]
      when "practice" then sessions.where(course: nil)
      when "match" then sessions.where(course: "match")
      when "final" then sessions.where.not(course: [ nil, "match" ])
      else sessions
      end
      sessions = sessions.where(gun_id: @filters[:gun]) if @filters[:gun]
      sessions = sessions.where(pellet_id: @filters[:pellet]) if @filters[:pellet]
      sessions = sessions.where(id: SessionExercise.where(exercise_id: @filters[:exercise]).select(:practice_session_id)) if @filters[:exercise]
      sessions = sessions.where(started_at: @filters[:days].to_i.days.ago..) if PERIODS.key?(@filters[:days])
      sessions
    end
end
