# The journal's goal line, per target type: score per 60 shots in whole rings
# (the shooter's trials benchmark: 565 for air pistol). JSON keyed by TargetSpec
# key, so rifle can have its own.
class AddGoalsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :goals, :json, default: {}, null: false
  end
end
