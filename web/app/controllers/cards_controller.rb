# One card of a session - any card, not only the current one the range screen
# shows: its target with the shots, its numbers, and every shot, each deletable.
class CardsController < ApplicationController
  def show
    @session = Current.user.practice_sessions.includes(cards: :shots).find(params[:practice_session_id])
    @card = @session.cards.find { it.number == params[:number].to_i } or raise ActiveRecord::RecordNotFound
    numbers = @session.cards.map(&:number)
    @previous, @next = numbers.select { it < @card.number }.max, numbers.select { it > @card.number }.min
  end
end
