# The session diary (journal groundwork): what was practised as tags the shooter
# taps (exercises, remembered per user), and three free-text boxes - problems,
# what fixed them, what was learned - kept apart so the journal can list every
# problem across sessions. No location or weather: Spotter is an at-home rig.
class AddDiaryToPracticeSessions < ActiveRecord::Migration[8.1]
  def change
    change_table :practice_sessions do |t|
      t.text :problems
      t.text :fixes
      t.text :learned
    end

    create_table :exercises do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.timestamps
    end

    create_table :session_exercises do |t|
      t.references :practice_session, null: false, foreign_key: true
      t.references :exercise, null: false, foreign_key: true
      t.timestamps
    end
    add_index :session_exercises, %i[ practice_session_id exercise_id ], unique: true
  end
end
