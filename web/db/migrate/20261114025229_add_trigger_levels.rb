# The sound trigger's level, per microphone (2026-11-13): the laptop's browser
# heard some shots at +58..+62 dB, under the engine's fixed +62. Set in the sound
# check (users.trigger_levels, {mic => dB}); each session records the level it ran
# with (practice_sessions.trigger_db), passed to the engine as --trigger-db.
class AddTriggerLevels < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :trigger_levels, :json
    add_column :practice_sessions, :trigger_db, :float
  end
end
