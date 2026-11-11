class PracticeSessionsController < ApplicationController
  before_action :set_session, only: %i[ show stop destroy ]

  def index
    @sessions = Current.user.practice_sessions.newest_first.includes(cards: :shots)
    @running = EngineRunner.running
  end

  # The range screen: live while the session runs, its record afterwards.
  def show
    EngineRunner.reconcile!(@session)
  end

  # Start: create the session and launch the engine for it.
  def create
    params = start_params
    camera = params[:camera] == "url" ? params[:camera_url] : params[:camera]
    session = EngineRunner.start!(user: Current.user, target: params[:target], per_card: params[:per_card],
                                  camera:, mic: params[:mic])
    redirect_to practice_session_path(session)
  rescue EngineRunner::BadCamera => e
    redirect_to practice_sessions_path, alert: "#{e.message.capitalize}."
  rescue RigCheck::Busy => e
    redirect_to practice_sessions_path, alert: "#{e.message.capitalize}."
  rescue EngineRunner::Busy => e
    redirect_to practice_sessions_path, alert: "#{e.message} - one session at a time on this rig."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to practice_sessions_path, alert: e.record.errors.full_messages.to_sentence
  end

  # Stop: the same as Ctrl+C - the engine does its final check, then ends the session.
  def stop
    EngineRunner.stop!(@session)
    redirect_to practice_session_path(@session)   # the header says "Stopping…" until it has
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
      params.expect(practice_session: [ :target, :per_card, :camera, :camera_url, :mic ])
    end
end
