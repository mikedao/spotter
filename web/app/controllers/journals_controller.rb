# The journal: trends across sessions (score per 60 against the goal, 10-shot
# series), the sessions with their numbers, and the diary's problems, fixes and
# lessons - filtered by type, kind, gun, pellets, exercise and period.
class JournalsController < ApplicationController
  def show
    @journal = Journal.new(Current.user, params.permit(:target, :kind, :gun, :pellet, :exercise, :days))
  end

  # The goal line: score per 60 shots for a target type (blank = none).
  def update
    target = params[:target].presence_in(TargetSpec::SPECS.keys) || "pistol"
    goal = params[:goal].to_s.strip
    unless goal.empty? || goal.match?(/\A\d{3}\z/) && goal.to_i.between?(300, 654)
      return redirect_to journal_path(target:), alert: "A goal is a score out of 600, like 565."
    end

    Current.user.update!(goals: (Current.user.goals || {}).merge(target => goal.presence&.to_i))
    redirect_to journal_path(target:), notice: goal.empty? ? "Goal line removed." : "Goal set to #{goal}."
  end
end
