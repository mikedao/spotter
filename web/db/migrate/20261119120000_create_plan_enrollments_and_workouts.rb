# The training plan (TrainingPlan): which day a user started it, and what they
# finished since. The plan's days are data in config/training_plan.yml; a
# plan_workouts row exists only once there is something to say about a day (a
# session started for it, a note, a tick).
class CreatePlanEnrollmentsAndWorkouts < ActiveRecord::Migration[8.1]
  def change
    create_table :plan_enrollments do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.date :started_on, null: false
      t.timestamps
    end

    create_table :plan_workouts do |t|
      t.references :plan_enrollment, null: false, foreign_key: true
      t.integer :week, null: false
      t.integer :day, null: false
      t.references :practice_session, foreign_key: true
      t.datetime :completed_at
      t.text :note
      t.timestamps
    end
    add_index :plan_workouts, %i[ plan_enrollment_id week day ], unique: true
  end
end
