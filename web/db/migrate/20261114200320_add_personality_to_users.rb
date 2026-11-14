class AddPersonalityToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :personality, :string
  end
end
