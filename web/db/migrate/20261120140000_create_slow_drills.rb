# The slow dry fire timer's results (SlowDrill): paced shots, each fired in time or let down.
class CreateSlowDrills < ActiveRecord::Migration[8.1]
  def change
    create_table :slow_drills do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :shots, null: false
      t.integer :string_size, null: false
      t.integer :limit_seconds, null: false
      t.integer :between_seconds, null: false
      t.integer :string_rest_seconds, null: false
      t.integer :shots_fired, null: false, default: 0
      t.integer :let_downs, null: false, default: 0
      t.float :break_seconds, null: false, default: 0   # summed raise-to-break time of the shots fired
      t.integer :plan_week
      t.integer :plan_day
      t.datetime :performed_at, null: false
      t.timestamps
    end
    add_index :slow_drills, %i[ user_id performed_at ]
  end
end
