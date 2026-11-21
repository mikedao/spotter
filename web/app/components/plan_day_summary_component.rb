# A finished training-plan day at a glance (the day page, once ticked done): each
# block with something to measure - a timer or a Spotter session - with its
# headline ("10/10", a score), whether it finished the block, and every run or
# session done for it with its own numbers; then the day's note. From
# PlanDayShare, so it says what the CompetitiveShooter.org post says.
class PlanDaySummaryComponent < ApplicationComponent
  def initialize(share:) = @share = share

  def render? = @share.summary.any? || @share.note.present?

  def items = @share.summary
  def note = @share.note

  # One run's line: when, and what it came to.
  def run_text(run)
    case run
    when PlanDayShare::SessionNumbers then run.text
    when SlowDrill
      [ run.summary, ("#{run.mean_break_seconds} s to break" if run.mean_break_seconds),
        ("#{run.first_time_rate}% first time" if run.first_time_rate) ].compact.join(" · ")
    when HoldDrill then [ run.summary, "#{run.held_seconds.round} s held" ].join(" · ")
    else run.summary
    end
  end

  def run_time(run) = (run.is_a?(PlanDayShare::SessionNumbers) ? run.session.started_at : run.performed_at).strftime("%H:%M")
  def run_link(run) = (helpers.practice_session_path(run.session) if run.is_a?(PlanDayShare::SessionNumbers))
end
