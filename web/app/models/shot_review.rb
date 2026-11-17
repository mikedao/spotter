# Walking through a session's shots to call them. Only the shots worth a look
# are visited (the shooter, 2026-11-17: "going through every single shot is a
# lot"): the rules' flags (line call, ring uncertain, overlaps a hole) and any
# shot where the live model's ring differs from the rules' - those decide the
# engine-vs-model comparison, so they always get a real call.
#
# "Save and next" goes to the next such shot without a call yet after this one,
# wrapping round to the start, so starting at shot 5 still visits 1-4. The save
# that finishes them returns to the session and ACCEPTS every other uncalled
# shot as scored (a call of the rules' own ring, no tap - what saving it
# unchanged did before), so the session counts as reviewed for ml:update.
# Re-checking when every shot already has a call steps on through the shots
# worth a look, in order, back to the session after the last one.
#
#   review = ShotReview.new(shot)
#   review.position / review.count   # 5 / 10 (of every scored shot)
#   review.previous, review.following # neighbours in order (nil at the ends)
#   review.after_save                 # where Save goes; nil = back to the session
#   review.left                       # shots to look at still without a call, this one aside
#   review.accept_rest!               # call every other uncalled shot as scored
class ShotReview
  attr_reader :shot

  def initialize(shot)
    @shot = shot
  end

  def self.worth_a_look?(shot) = shot.flagged? || shot.model_disagrees?

  # A BLIND call (the shooter, 2026-11-17): a shot worth a look with no call yet
  # is shown without the engine's or model's estimates, score or ring, so the
  # call is the shooter's own - an anchored call hands the tie to whoever was
  # shown. Revealed once called (re-checking shows everything).
  def blind? = self.class.worth_a_look?(shot) && !shot.called?

  def shots
    @shots ||= Shot.joins(:card).where(cards: { practice_session_id: shot.card.practice_session_id }, status: "scored")
                   .order("cards.number", :fired_at, :id).to_a
  end

  def index = shots.index(shot) || 0
  def position = index + 1
  def count = shots.size
  def previous = index.positive? ? shots[index - 1] : nil
  def following = shots[index + 1]

  def to_look_at = shots.select { self.class.worth_a_look?(it) }
  def uncalled = to_look_at.reject { it == shot || it.called? }
  def left = uncalled.size

  # Ask BEFORE saving the call (the controller does): if this save completes the
  # review, back to the session; if this shot already had a call (re-checking),
  # step on to the next shot worth a look.
  def after_save
    later = shots.drop(index + 1)
    return (shot.called? ? later.find { self.class.worth_a_look?(it) } : nil) if uncalled.empty?

    later.find { uncalled.include?(it) } || uncalled.first
  end

  # The rest were not worth a look: accept them as scored. Never this shot (its
  # call was just saved; the copy in `shots` predates it). Returns how many.
  def accept_rest!
    rest = shots.reject { it == shot || it.called? || self.class.worth_a_look?(it) }
    rest.each { it.record_call!(ring: it.ring) }
    rest.size
  end
end
