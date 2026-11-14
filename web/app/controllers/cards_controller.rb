# One card of a session - any card, not only the current one the range screen
# shows: its target with the shots, its numbers, and every shot, each deletable -
# and the card itself (Card#remove!), but not the one on the target mid-session.
class CardsController < ApplicationController
  before_action :set_card

  def show
    numbers = @session.cards.map(&:number)
    @previous, @next = numbers.select { it < @card.number }.max, numbers.select { it > @card.number }.min
  end

  def destroy
    if @card.on_target?
      return redirect_to(practice_session_card_path(@session, @card.number), status: :see_other,
                         alert: "Card #{@card.number} is on the target - change cards first, then delete it.")
    end

    shots = @card.shots.count { it.scored? }
    EngineRunner.forget!(@session, @card.shots.to_a) if @session.live?
    @card.remove!
    LiveBroadcast.new(@session.reload).call if @session.live?
    redirect_to practice_session_path(@session), status: :see_other,
                notice: "Deleted card #{@card.number}#{" and its #{shots == 1 ? 'shot' : "#{shots} shots"}" if shots.positive?}."
  end

  private
    # Only the owner's sessions: another user's is a 404.
    def set_card
      @session = Current.user.practice_sessions.includes(cards: :shots).find(params[:practice_session_id])
      @card = @session.cards.find { it.number == params[:number].to_i } or raise ActiveRecord::RecordNotFound
    end
end
