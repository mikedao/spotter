# A capture the engine could not score that the shooter scored by tapping the
# hole on its picture (Shot#score_by_hand!): when they did. Marks the shot as
# placed by the shooter, not found by the system - kept apart, like a call.
class AddPinpointedAtToShots < ActiveRecord::Migration[8.1]
  def change
    add_column :shots, :pinpointed_at, :datetime
  end
end
