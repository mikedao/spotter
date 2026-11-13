class PracticeSessionsController < ApplicationController
  before_action :set_session, only: %i[ show update diary stop start_match refind resume destroy ]

  def index
    @sessions = Current.user.practice_sessions.newest_first.includes(:gun, :pellet, cards: :shots)
    @running = EngineRunner.running
  end

  # The range screen: live while the session runs, its record afterwards.
  def show
    EngineRunner.reconcile!(@session)
  end

  # Start: the setup wizard's last step. Create the session and launch the
  # engine for it, once this user's checks have let go of the camera and mic.
  def create
    params = start_params
    RigCheck.stop_for!(Current.user)
    gear = GearParams.new(Current.user, gear_params).attributes
    session = EngineRunner.start!(user: Current.user, target: params[:target], per_card: params[:per_card],
                                  camera: params[:camera], mic: params[:mic], course: params[:course], gear:)
    redirect_to practice_session_path(session)
  rescue EngineRunner::BadCamera => e
    redirect_to setup_start_path, alert: "#{e.message.upcase_first}."
  rescue RigCheck::Busy => e
    redirect_to setup_start_path, alert: "#{e.message.upcase_first}."
  rescue EngineRunner::Busy => e
    redirect_to practice_sessions_path, alert: "#{e.message} - one session at a time on this rig."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to setup_start_path, alert: e.record.errors.full_messages.to_sentence
  end

  # The session's gun, pellets and gun adjustments - set at the start, changeable
  # any time (during the session or after), from the session page.
  def update
    if @session.update(GearParams.new(Current.user, gear_params).attributes)
      redirect_to practice_session_path(@session, anchor: "gear"), notice: "Saved the gun and pellets.", status: :see_other
    else
      redirect_to practice_session_path(@session, anchor: "gear"), alert: "#{@session.errors.full_messages.to_sentence}.", status: :see_other
    end
  rescue ActiveRecord::RecordInvalid => e
    redirect_to practice_session_path(@session, anchor: "gear"), alert: "#{e.record.errors.full_messages.to_sentence}.", status: :see_other
  end

  # The session diary: exercise tags, problems, what fixed them, what was learned.
  def diary
    DiaryParams.new(Current.user, diary_params).apply!(@session)
    redirect_to practice_session_path(@session, anchor: "diary"), notice: "Saved the diary.", status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_to practice_session_path(@session, anchor: "diary"), alert: "#{e.record.errors.full_messages.to_sentence}.", status: :see_other
  end

  # Stop: the same as Ctrl+C - the engine does its final check, then ends the session.
  def stop
    EngineRunner.stop!(@session)
    redirect_to practice_session_path(@session)   # the header says "Stopping…" until it has
  end

  # "Re-find target": the engine re-locates the card (after a bump). No page
  # load - that would stop the sound; the status line and "ready" answer it.
  def refind
    EngineRunner.refind!(@session) ? head(:no_content) : head(:conflict)   # 409: an engine too old for it
  end

  # Continue a finished practice session from today: the engine starts again on
  # the same session, rig and gear, and works out whether the card on the target
  # carries on or a new one starts.
  def resume
    RigCheck.stop_for!(Current.user)
    EngineRunner.continue!(@session)
    redirect_to practice_session_path(@session)
  rescue EngineRunner::NotContinuable, RigCheck::Busy => e
    redirect_to practice_session_path(@session), alert: "#{e.message.upcase_first}."
  rescue EngineRunner::Busy => e
    redirect_to practice_session_path(@session), alert: "#{e.message} - one session at a time on this rig."
  end

  # "Start match": end the sighting time now; the range officer calls the match.
  def start_match
    EngineRunner.start_match!(@session)
    redirect_to practice_session_path(@session)
  end

  # Delete a finished session and everything in it (cards, shots, your calls,
  # pictures). A running one must be stopped first.
  def destroy
    EngineRunner.reconcile!(@session)   # a session whose engine died is over
    if @session.destroy
      redirect_to practice_sessions_path, notice: "Deleted #{@session.title}.", status: :see_other
    else
      redirect_to practice_session_path(@session), alert: "#{@session.errors.full_messages.to_sentence}.", status: :see_other
    end
  end

  # The live camera picture, relayed from the engine (which holds the camera and
  # serves it on 127.0.0.1 only), so it stays behind the login and works from a
  # phone. Polled a few times a second by live_camera_controller.js; 204 = none
  # right now, 410 = the session is over (the page then drops the picture).
  def camera
    session = Current.user.practice_sessions.find(params[:id])
    return head(:gone) unless session.live?

    jpeg = EngineRunner.snapshot(session)
    return head(:no_content) unless jpeg

    response.headers["Cache-Control"] = "no-store"
    send_data jpeg, type: "image/jpeg", disposition: "inline"
  end

  private
    def set_session
      @session = Current.user.practice_sessions.includes(cards: :shots).find(params[:id])
    end

    def start_params
      params.expect(practice_session: [ :target, :per_card, :camera, :mic, :course ])
    end

    def diary_params
      params.fetch(:practice_session, {}).permit(:new_exercise, :problems, :fixes, :learned, exercise_ids: [])
    end

    def gear_params
      params.fetch(:practice_session, {}).permit(:gun_id, :pellet_id, :gun_adjustments,
                                                 new_pellet: %i[ name lot weight_grains head_mm ])
    end
end
