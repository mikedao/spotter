# One run of the guided hold drill (HoldDrill): raise, hold, lower, rest, repeated.
# plan_week / plan_day say which day of the training plan it was done for, if any.
class CreateHoldDrills < ActiveRecord::Migration[8.1]
  def change
    create_table :hold_drills do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :reps, null: false
      t.integer :hold_seconds, null: false
      t.integer :rest_seconds, null: false
      t.integer :reps_done, null: false, default: 0
      t.integer :let_downs, null: false, default: 0
      t.float :held_seconds, null: false, default: 0
      t.integer :plan_week
      t.integer :plan_day
      t.datetime :performed_at, null: false
      t.timestamps
    end
    add_index :hold_drills, %i[ user_id performed_at ]
  end
end
