# The order the plan's days are on the calendar, once the shooter has moved any
# (JSON: ["1-1", "1-2", ...], one reference per calendar day; null = as written).
class AddScheduleToPlanEnrollments < ActiveRecord::Migration[8.1]
  def change
    add_column :plan_enrollments, :schedule, :text
  end
end
