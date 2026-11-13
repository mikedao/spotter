# A continued session: the time it stood finished before Continue, left out of
# its duration.
class AddBreakSecondsToPracticeSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :practice_sessions, :break_seconds, :integer, default: 0, null: false
  end
end
