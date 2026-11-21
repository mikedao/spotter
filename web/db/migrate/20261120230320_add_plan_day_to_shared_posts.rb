class AddPlanDayToSharedPosts < ActiveRecord::Migration[8.1]
  def change
    add_column :shared_posts, :plan_week, :integer
    add_column :shared_posts, :plan_day, :integer
  end
end
