# The timed-fire timer: pick the strings (or arrive from a plan day with them), run
# it on a timer page, and keep what it reports (TimedDrill). Dry fire, Pardini.
class TimedDrillsController < ApplicationController
  def index
    @settings = TimedDrill.settings(params)
    @drills = Current.user.timed_drills.newest_first.limit(20)
  end

  # ?strings=&seconds=&shots=&rest= (clamped), ?plan_day=1-2 when started from the plan.
  def new
    @settings = TimedDrill.settings(strings: params[:strings], string_seconds: params[:seconds], shots: params[:shots], rest_seconds: params[:rest])
    @plan_day = plan_day_ref
    @voice = Voice.picked(Current.user)
    @cues = TimedDrill::CUES.to_h { [ it, Voice.piece_url(@voice.id, it) ] }
  end

  def create
    drill = Current.user.timed_drills.new(result_params.merge(performed_at: Time.current))
    if (ref = plan_day_ref) then drill.plan_week, drill.plan_day = TrainingPlan.parse(ref) end
    if drill.save
      redirect_to (drill.plan_ref ? plan_workout_path(drill.plan_week, drill.plan_day) : timed_drills_path),
                  notice: "Saved: #{drill.summary}.", status: :see_other
    else
      redirect_to timed_drills_path, alert: "#{drill.errors.full_messages.to_sentence}.", status: :see_other
    end
  end

  private
    def plan_day_ref
      ref = params[:plan_day].presence
      ref if ref && Current.user.plan_enrollment && TrainingPlan.parse(ref)
    end

    def result_params = params.expect(timed_drill: %i[ strings shots string_seconds rest_seconds strings_done ])
end
