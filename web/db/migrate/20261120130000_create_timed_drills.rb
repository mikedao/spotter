# The timed-fire timer's results (TimedDrill): strings of shots against the clock.
class CreateTimedDrills < ActiveRecord::Migration[8.1]
  def change
    create_table :timed_drills do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :strings, null: false
      t.integer :shots, null: false
      t.integer :string_seconds, null: false
      t.integer :rest_seconds, null: false
      t.integer :strings_done, null: false, default: 0
      t.integer :plan_week
      t.integer :plan_day
      t.datetime :performed_at, null: false
      t.timestamps
    end
    add_index :timed_drills, %i[ user_id performed_at ]
  end
end
