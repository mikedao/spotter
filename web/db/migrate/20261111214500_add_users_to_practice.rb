# Users own their practice sessions (each shooter sees only their own), and a
# session started from the web app carries what it needs to run the engine: a
# one-time token the engine's events must present, the engine's process id and
# log file, and the shots-per-card setting.
class AddUsersToPractice < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :name, :string, null: false, default: ""

    add_reference :practice_sessions, :user, null: false, foreign_key: true
    add_column :practice_sessions, :run_token, :string
    add_column :practice_sessions, :per_card, :integer
    add_column :practice_sessions, :engine_pid, :integer
    add_column :practice_sessions, :engine_log, :string
    add_column :practice_sessions, :engine_error, :text
    add_index :practice_sessions, :run_token, unique: true
  end
end
