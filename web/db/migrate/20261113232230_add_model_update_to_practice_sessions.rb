class AddModelUpdateToPracticeSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :practice_sessions, :model_update, :json
  end
end
