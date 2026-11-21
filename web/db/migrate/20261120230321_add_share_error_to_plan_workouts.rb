class AddShareErrorToPlanWorkouts < ActiveRecord::Migration[8.1]
  def change
    add_column :plan_workouts, :share_error, :string
  end
end
