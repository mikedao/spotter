# Seconds from a shot's sound to its score (heard and seen/heard shots), so the
# shooter can see how quickly each is found - and whether it slows over a session.
class AddDetectSecondsToShots < ActiveRecord::Migration[8.1]
  def change
    add_column :shots, :detect_seconds, :float
  end
end
