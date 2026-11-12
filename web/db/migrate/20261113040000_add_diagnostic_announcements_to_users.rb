# The announcer's diagnostic mode (Settings): off = after a shot, only its number,
# score and direction (and scoring facts: sighter, out of time); on = also why a
# shot is worth a look (line call, overlaps a hole, found without a sound...).
class AddDiagnosticAnnouncementsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :diagnostic_announcements, :boolean, default: false, null: false
  end
end
