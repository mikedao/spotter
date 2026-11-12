# The last sound check that heard a shot, per user: which microphone, when, how
# loud. With the same microphone (still connected) the session wizard skips the
# sound check next time - the shooter asked not to redo it for a setup that
# passed before. "Check again" on the Start step always can.
class AddSoundCheckToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :sound_check, :json
  end
end
