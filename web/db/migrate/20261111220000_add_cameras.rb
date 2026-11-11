# The shooter picks the camera when starting a session (camera index or a stream
# URL such as the Pi's); remembered per user, recorded per session.
class AddCameras < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :last_camera, :string
    add_column :practice_sessions, :camera, :string
  end
end
