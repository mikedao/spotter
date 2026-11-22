class AddMatchDaysToPlanEnrollments < ActiveRecord::Migration[8.1]
  def change
    add_column :plan_enrollments, :match_days, :json, default: [], null: false
  end
end
