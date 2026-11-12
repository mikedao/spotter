# The session page's Diary: what was practiced (exercise tags to tap, plus a box
# to add a new one) and three boxes - problems, what fixed them, what was
# learned. Filled in any time, during the session or after. Outside everything
# LiveBroadcast replaces, so a shot never resets a half-written note.
class SessionDiaryComponent < ApplicationComponent
  INPUT = TextFieldComponent::INPUT
  BOXES = [
    [ :problems, "Problems", "What went wrong: a flinch, a pulled shot, losing the hold…" ],
    [ :fixes, "What fixed it", "What helped, or what you'll try next time" ],
    [ :learned, "What I learned", "Anything to remember" ]
  ].freeze

  def initialize(session:) = @session = session

  private
    attr_reader :session

    def exercises = (session.user.exercises.by_use.to_a | session.exercises.to_a)
    def chosen?(exercise) = session.exercise_ids.include?(exercise.id)
end
