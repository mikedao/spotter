class AddVoiceToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :voice, :string
  end
end
