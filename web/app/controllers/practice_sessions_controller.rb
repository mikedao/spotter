class PracticeSessionsController < ApplicationController
  def index
    @sessions = PracticeSession.newest_first.includes(cards: :shots)
  end

  # The range screen: live while the session runs, its record afterwards.
  def show
    @session = PracticeSession.includes(cards: :shots).find(params[:id])
  end
end
