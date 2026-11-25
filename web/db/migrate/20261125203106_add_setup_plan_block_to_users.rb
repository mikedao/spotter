class AddSetupPlanBlockToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :setup_plan_block, :string
  end
end
