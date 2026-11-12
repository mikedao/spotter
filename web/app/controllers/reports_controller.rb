# A session as a printable report (Save as PDF from the browser's print dialog):
# the scores and series, each card's target with its shots, the gun, pellets and
# exercises, and the diary - for the shooter's records or a coach.
class ReportsController < ApplicationController
  layout "report"

  def show
    @session = Current.user.practice_sessions.includes(:gun, :pellet, :exercises, cards: :shots).find(params[:practice_session_id])
    @summary = SessionSummary.new(@session)
    @event = EventStats.new(@session) if @session.course
  end
end
