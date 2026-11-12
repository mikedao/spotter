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

  def charted = summaries.select(&:charted?)
  def newest_first = summaries.reverse
  def with_notes = newest_first.select { [ it.problems, it.fixes, it.learned ].any?(&:present?) }

  # What the filter menus offer: only what the shooter has.
  def guns = user.guns.of_kind(target).by_name
  def pellets = user.pellets.by_name
  def exercises = user.exercises.by_use

  private
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
