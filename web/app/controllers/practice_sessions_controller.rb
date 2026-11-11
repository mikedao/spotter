class PracticeSessionsController < ApplicationController
  before_action :set_session, only: %i[ show stop ]

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
  rescue EngineRunner::Busy => e
    redirect_to practice_sessions_path, alert: "#{e.message} - one session at a time on this rig."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to practice_sessions_path, alert: e.record.errors.full_messages.to_sentence
  end

  # Stop: the same as Ctrl+C - the engine does its final check, then ends the session.
  def stop
    EngineRunner.stop!(@session)
    redirect_to practice_session_path(@session), notice: "Stopping - the engine does a last check for an unscored hole first."
  end

  private
    def set_session
      @session = Current.user.practice_sessions.includes(cards: :shots).find(params[:id])
    end

    def start_params
      params.expect(practice_session: [ :target, :per_card, :camera, :camera_url, :mic ])
    end
end
