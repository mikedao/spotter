# The top of the Practice page (PracticeHome): a few numbers on how training
# has been going, then BIG buttons for each kind of training - today's plan day
# first when there is one - each saying when it was last done.
class PracticeHomeComponent < ApplicationComponent
  # A whole tile is the link. Big enough to hit from the firing line.
  TILE = "group flex min-h-32 flex-col rounded-xl border p-5 text-left transition focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-600".freeze
  PLAIN = "border-gray-200 bg-white hover:border-blue-400 hover:bg-blue-50 dark:border-gray-800 dark:bg-gray-900 dark:hover:border-blue-500 dark:hover:bg-gray-800".freeze
  HERO = "border-blue-600 bg-blue-600 text-white hover:bg-blue-500 dark:border-blue-500".freeze
  LIVE = "border-green-600 bg-green-600 text-white hover:bg-green-500 dark:border-green-500".freeze
  KICKER = "text-xs font-semibold uppercase tracking-wide".freeze

  def initialize(home:) = @home = home

  private
    attr_reader :home

    # One blue button at a time: today's plan day while it is still to do, else New session.
    def shoot_first? = !(home.plan_day && !home.plan_day_done?)

    # The summary row: [ label, value, note ].
    def stats
      @stats ||= [ last_session_stat, pace_stat, week_stat, (plan_stat if home.enrollment) ].compact
    end

    def last_session_stat
      summary = home.last_session_summary
      return [ "Last session", "–", "none yet" ] unless summary

      value = summary.count.zero? ? "–" : (summary.per_60 ? "#{summary.per_60}" : "#{summary.total}")
      note = if summary.count.zero? then "no shots · #{when_text(summary.started_at)}"
      elsif summary.per_60 then "per 60 · #{when_text(summary.started_at)}"
      else "#{helpers.pluralize(summary.count, 'shot')} · #{when_text(summary.started_at)}"
      end
      [ "Last session", value, note ]
    end

    def pace_stat
      pace = home.recent_pace
      return [ "Recent pace", "–", "after a session of 10+ shots" ] unless pace

      [ "Recent pace", pace, "per 60, last #{helpers.pluralize(home.pace_sessions, 'session')}" ]
    end

    def week_stat
      streak = home.streak
      note = if streak > 1 then "#{streak} days in a row"
      elsif home.trained_today? then "trained today"
      else "not yet today"
      end
      [ "This week", "#{home.days_trained} of #{PracticeHome::WEEK}", "days trained · #{note}" ]
    end

    def plan_stat
      [ "Training plan", "#{home.enrollment.done_count} of #{home.enrollment.workout_count}", "workouts done" ]
    end

    # "today", "yesterday", "Mon", "Nov 12".
    def when_text(time)
      return unless time

      days = (Time.zone.today - time.in_time_zone.to_date).to_i
      case days
      when 0 then "today"
      when 1 then "yesterday"
      when 2..6 then time.strftime("%a")
      else time.strftime(time.year == Time.zone.today.year ? "%b %-d" : "%b %-d, %Y")
      end
    end

    def last_text(kind)
      at = home.last_at(kind)
      at ? "Last: #{when_text(at)}" : "Not tried yet"
    end

    # The dry-fire and look-back tiles: [ kicker, title, what it is, path, last-done kind ].
    def tiles
      [
        [ "Dry fire", "Hold drills", "Raise, hold, let down. A guided timer.", helpers.hold_drills_path, :hold ],
        [ "Dry fire", "Slow dry fire", "Break each shot inside the time limit.", helpers.slow_drills_path, :slow ],
        [ "Dry fire", "Timed fire", "Strings of shots against the clock.", helpers.timed_drills_path, :timed ],
        [ "Look back", "Journal", "Scores, trends, series and where the misses go.", helpers.journal_path, nil ]
      ]
    end
end
