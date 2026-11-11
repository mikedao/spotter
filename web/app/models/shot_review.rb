# Walking through a session's shots to call them: every scored shot of the
# session, card by card, in the order fired - wherever the shooter started.
#
# "Save and next" goes to the next shot without a call yet after this one,
# wrapping round to the start, so starting at shot 5 still visits 1-4; the save
# that gives the last shot its call returns to the session. Re-checking when
# every shot already has a call steps on in order, back to the session after
# the last one.
#
#   review = ShotReview.new(shot)
#   review.position / review.count   # 5 / 10
#   review.previous, review.following # neighbours in order (nil at the ends)
#   review.after_save                 # where Save goes; nil = back to the session
#   review.left                       # shots still without a call, this one aside
class ShotReview
  attr_reader :shot

  def initialize(shot)
    @shot = shot
  end

  def shots
    @shots ||= Shot.joins(:card).where(cards: { practice_session_id: shot.card.practice_session_id }, status: "scored")
                   .order("cards.number", :fired_at, :id).to_a
  end

  def index = shots.index(shot) || 0
  def position = index + 1
  def count = shots.size
  def previous = index.positive? ? shots[index - 1] : nil
  def following = shots[index + 1]

  def uncalled = shots.reject { it == shot || it.called? }
  def left = uncalled.size

  # Ask BEFORE saving the call (the controller does): if this save completes the
  # review, back to the session; if this shot already had a call (re-checking),
  # step on in order.
  def after_save
    return (shot.called? ? following : nil) if uncalled.empty?

    later = shots.drop(index + 1)
    later.find { uncalled.include?(it) } || uncalled.first
  end
end
