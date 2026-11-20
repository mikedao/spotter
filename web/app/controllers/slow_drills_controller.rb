# The slow dry fire timer: pick the settings (or arrive from a plan day with them),
# run it on a timer page, and keep what it reports (SlowDrill). Pardini dry fire.
class SlowDrillsController < ApplicationController
  def index
    @settings = SlowDrill.settings(params)
    @drills = Current.user.slow_drills.newest_first.limit(20)
  end

  # ?shots=&limit=&between=&string=&string_rest= (clamped), ?plan_day=1-2 from the plan.
  def new
    @settings = SlowDrill.settings(shots: params[:shots], string_size: params[:string], limit_seconds: params[:limit],
                                   between_seconds: params[:between], string_rest_seconds: params[:string_rest])
    @plan_day = plan_day_ref
    @voice = Voice.picked(Current.user)
    @cues = SlowDrill::CUES.to_h { [ it, Voice.piece_url(@voice.id, it) ] }
  end

  def create
    drill = Current.user.slow_drills.new(result_params.merge(performed_at: Time.current))
    if (ref = plan_day_ref) then drill.plan_week, drill.plan_day = TrainingPlan.parse(ref) end
    if drill.save
      redirect_to (drill.plan_ref ? plan_workout_path(drill.plan_week, drill.plan_day) : slow_drills_path),
                  notice: "Saved: #{drill.summary}.", status: :see_other
    else
      redirect_to slow_drills_path, alert: "#{drill.errors.full_messages.to_sentence}.", status: :see_other
    end
  end

  private
    def plan_day_ref
      ref = params[:plan_day].presence
      ref if ref && Current.user.plan_enrollment && TrainingPlan.parse(ref)
    end

    def result_params
      params.expect(slow_drill: %i[ shots string_size limit_seconds between_seconds string_rest_seconds shots_fired let_downs break_seconds ])
    end
end
