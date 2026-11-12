# A practice session's exercise tag (Exercise).
class SessionExercise < ApplicationRecord
  belongs_to :practice_session
  belongs_to :exercise

  validates :exercise_id, uniqueness: { scope: :practice_session_id }
end
