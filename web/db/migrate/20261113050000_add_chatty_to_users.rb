# Chatty mode: the announcer also comments - streaks, bests, patterns, pace,
# summaries after each 10 shots and after a match (Commentary). On and off at
# will, in Settings or on the range screen. Later: personalities to pick from.
class AddChattyToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :chatty, :boolean, default: false, null: false
  end
end
