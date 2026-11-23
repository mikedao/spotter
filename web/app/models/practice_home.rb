# The Practice page - the first page after signing in: how training has been
# going lately, and when each kind of training was last done, so today's choice
# is easy to make.
#
#   home = PracticeHome.new(user, running: EngineRunner.running)
#   home.days_trained     # => 4   days with any training in the last 7
#   home.streak           # => 3   days in a row, back from today (or yesterday)
#   home.last(:hold)      # => the newest hold drill, or nil
class PracticeHome
  WEEK = 7

  attr_reader :user, :running

  def initialize(user, running: nil, today: Time.zone.today)
    @user = user
    @running = running
    @today = today
  end

  def live_session = (running if running&.user == user)
  def someone_else_shooting = (running if running && running.user != user)

  def enrollment = user.plan_enrollment
  def plan_day = enrollment&.today
  def plan_day_done? = plan_day && enrollment.done?(plan_day.week, plan_day.day)

  # The newest of each kind of training.
  def last(kind)
    @last ||= {}
    @last.fetch(kind) do
      @last[kind] = case kind
      when :session then user.practice_sessions.newest_first.first
      when :hold then user.hold_drills.newest_first.first
      when :slow then user.slow_drills.newest_first.first
      when :timed then user.timed_drills.newest_first.first
      end
    end
  end

  def last_at(kind) = last(kind)&.then { kind == :session ? it.started_at : it.performed_at }

  def last_session_summary = last(:session)&.then { SessionSummary.new(it) }

  # The Journal's own headline number, so the two pages never disagree.
  def recent_pace = journal.recent_pace
  def pace_sessions = [ journal.charted.size, Journal::RECENT ].min
  def journal = @journal ||= Journal.new(user)

  # Days with any training: a live session or a dry-fire drill.
  def days_trained = training_days.count { it > @today - WEEK }

  def streak
    day = training_days.include?(@today) ? @today : @today - 1   # today isn't over yet
    run = 0
    run, day = run + 1, day - 1 while training_days.include?(day)
    run
  end

  def trained_today? = training_days.include?(@today)

  # How far back training days are looked for: a streak tops out there.
  LOOK_BACK = 60

  private
    def training_days
      @training_days ||= begin
        since = (@today - LOOK_BACK).beginning_of_day
        times = user.practice_sessions.where(started_at: since..).pluck(:started_at) +
          [ user.hold_drills, user.slow_drills, user.timed_drills ].flat_map { it.where(performed_at: since..).pluck(:performed_at) }
        times.to_set { it.in_time_zone.to_date }
      end
    end
end
