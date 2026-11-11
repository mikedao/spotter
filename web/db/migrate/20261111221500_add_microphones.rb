# The shooter picks the microphone too (or none: camera only); remembered per
# user, recorded per session.
class AddMicrophones < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :last_mic, :string
    add_column :practice_sessions, :mic, :string
  end
end
