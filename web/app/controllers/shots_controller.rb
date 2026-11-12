# Reviewing one shot: its close-ups and how it was scored, and the shooter's call.
# The call is stored beside the rules' proposal, never over it (see Shot).
class ShotsController < ApplicationController
  before_action :set_shot

  def show
    @session = @shot.practice_session
    @review = ShotReview.new(@shot)
  end

  def update
    following = ShotReview.new(@shot).after_save   # decided before this call is saved
    @shot.record_call!(**call_params.to_h.symbolize_keys)
    LiveBroadcast.new(@shot.practice_session).call
    redirect_to(following ? shot_path(following) : practice_session_path(@shot.practice_session),
                notice: "Call saved for card #{@shot.card.number}, shot #{@shot.number}.")
  rescue ActiveRecord::RecordInvalid => e
    redirect_to shot_path(@shot), alert: e.record.errors.full_messages.to_sentence
  end

  # Delete a shot that wasn't a real one; the card renumbers, a live range
  # screen updates.
  def destroy
    session = @shot.practice_session
    card_number = @shot.card.number
    label = "card #{card_number}, shot #{@shot.number}"
    @shot.remove!
    LiveBroadcast.new(session.reload).call if session.live?
    back = params[:back] == "card" ? practice_session_card_path(session, card_number) : practice_session_path(session)
    redirect_to back, notice: "Deleted #{label}.", status: :see_other
  end

  private
    # Only the owner's shots: another user's id is a 404, not a peek.
    def set_shot
      @shot = Shot.joins(card: :practice_session)
                  .where(practice_sessions: { user_id: Current.user.id })
                  .includes(card: :practice_session).find(params[:id])
    end

    def call_params
      params.expect(shot: [ :ring, :decimal, :x_mm, :y_mm, :note ])
    end
end
