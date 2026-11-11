class AddStreamPortToPracticeSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :practice_sessions, :stream_port, :integer
  end
end
