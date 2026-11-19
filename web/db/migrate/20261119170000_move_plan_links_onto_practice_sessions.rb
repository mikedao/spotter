# A training plan day can now have several Spotter sessions - one per shooting
# block (Slow groups, Called shots...) - so the link lives on the session:
# plan_week / plan_day / plan_block (the block's number in its day; nil for a
# session started for a day as a whole, which is all there was before).
# plan_workouts keeps the day's note and tick, and loses its single session link.
class MovePlanLinksOntoPracticeSessions < ActiveRecord::Migration[8.1]
  def up
    add_column :practice_sessions, :plan_week, :integer
    add_column :practice_sessions, :plan_day, :integer
    add_column :practice_sessions, :plan_block, :integer
    add_index :practice_sessions, %i[ plan_week plan_day ]

    execute <<~SQL
      UPDATE practice_sessions
      SET plan_week = (SELECT week FROM plan_workouts WHERE plan_workouts.practice_session_id = practice_sessions.id),
          plan_day = (SELECT day FROM plan_workouts WHERE plan_workouts.practice_session_id = practice_sessions.id)
      WHERE id IN (SELECT practice_session_id FROM plan_workouts WHERE practice_session_id IS NOT NULL)
    SQL

    remove_reference :plan_workouts, :practice_session, foreign_key: true, index: true
  end

  def down
    add_reference :plan_workouts, :practice_session, foreign_key: true, index: true
    remove_index :practice_sessions, %i[ plan_week plan_day ]
    remove_column :practice_sessions, :plan_block
    remove_column :practice_sessions, :plan_day
    remove_column :practice_sessions, :plan_week
  end
end
