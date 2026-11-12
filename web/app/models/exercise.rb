# What a session practiced, as a tag the shooter taps ("trigger control",
# "5-shot strings"). Typed once, then offered as a tag in every later session;
# a session can have several. Tags no session uses any more go away by
# themselves (Exercise.tidy!), so there is no list to manage.
class Exercise < ApplicationRecord
  belongs_to :user
  has_many :session_exercises, dependent: :destroy
  has_many :practice_sessions, through: :session_exercises

  normalizes :name, with: ->(n) { n.squish }

  validates :name, presence: true, length: { maximum: 40 }
  validates :name, uniqueness: { scope: :user_id, case_sensitive: false }

  # The user's tags, most used first.
  scope :by_use, -> {
    left_joins(:session_exercises).group(:id)
      .order(Arel.sql("COUNT(session_exercises.id) DESC"), Arel.sql("lower(exercises.name)"))
  }

  def self.tidy!(user) = user.exercises.where.missing(:session_exercises).destroy_all
end
