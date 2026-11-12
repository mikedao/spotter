# Match and final: a session runs a course of fire (engine/course.py) or none
# (practice). Its live phase (what the range officer last called, and when the
# current window closes) is kept for the range screen's clock; each shot records
# whether it was a sighter or a match shot, its series and number in the event,
# and why it scores zero if it was out of time.
class AddCourses < ActiveRecord::Migration[8.1]
  def change
    add_column :practice_sessions, :course, :string
    add_column :practice_sessions, :course_state, :json

    add_column :shots, :stage, :string
    add_column :shots, :series, :integer
    add_column :shots, :match_number, :integer
    add_column :shots, :penalty, :string
  end
end
