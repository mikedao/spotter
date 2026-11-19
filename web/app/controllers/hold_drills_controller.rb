# The guided hold drill: pick the settings (or arrive from a plan day with them),
# run it on a timer page, and keep what it reports (HoldDrill).
class HoldDrillsController < ApplicationController
  # Start one with your own settings, and see the ones you have done.
  def index
    @settings = HoldDrill.settings(params)
    @drills = Current.user.hold_drills.newest_first.limit(20)
  end

  # The timer page. ?reps=&hold=&rest= (clamped), ?plan_day=3-2 when started from the plan.
  def new
    @settings = HoldDrill.settings(reps: params[:reps], hold_seconds: params[:hold], rest_seconds: params[:rest])
    @plan_day = plan_day_ref
    @voice = Voice.picked(Current.user)
    @cues = HoldDrill::CUES.to_h { [ it, Voice.piece_url(@voice.id, it) ] }   # where the browser gets each cue, in the user's voice
  end

  def create
    drill = Current.user.hold_drills.new(result_params.merge(performed_at: Time.current))
    if (ref = plan_day_ref) then drill.plan_week, drill.plan_day = TrainingPlan.parse(ref) end
    if drill.save
      redirect_to after_path(drill), notice: "Saved: #{drill.summary}.", status: :see_other
    else
      redirect_to hold_drills_path, alert: "#{drill.errors.full_messages.to_sentence}.", status: :see_other
    end
  end

  private
    # A plan day only counts for someone following the plan.
    def plan_day_ref
      ref = params[:plan_day].presence
      ref if ref && Current.user.plan_enrollment && TrainingPlan.parse(ref)
    end

    def after_path(drill) = drill.plan_ref ? plan_workout_path(drill.plan_week, drill.plan_day) : hold_drills_path

    def result_params = params.expect(hold_drill: %i[ reps hold_seconds rest_seconds reps_done let_downs held_seconds ])
end
