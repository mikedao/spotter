# The session page's Diary form -> a session's diary: the exercise tags ticked
# (looked up through the user, so another user's tag id is ignored), a new tag
# typed in (or the existing one of that name), and the three boxes.
#
#   DiaryParams.new(user, params[:practice_session]).apply!(session)
class DiaryParams
  def initialize(user, params)
    @user = user
    @params = params || {}
  end

  def apply!(session)
    PracticeSession.transaction do
      exercises = @user.exercises.where(id: Array(@params[:exercise_ids]).compact_blank).to_a
      exercises |= [ new_exercise ].compact
      session.update!(exercises:, problems: text(:problems), fixes: text(:fixes), learned: text(:learned))
      Exercise.tidy!(@user)
    end
  end

  private
    def text(key) = @params[key].to_s.strip.presence

    def new_exercise
      name = @params[:new_exercise].to_s.squish
      return if name.blank?

      @user.exercises.where("lower(name) = ?", name.downcase).first || @user.exercises.create!(name:)
    end
end
