class AddGroupOfToPracticeSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :practice_sessions, :group_of, :integer
  end
end
