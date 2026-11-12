# Shooters sign in with a username and a PIN (stored as a bcrypt digest). The
# email address is kept but not used to sign in.
class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :username, null: false
      t.string :email_address, null: false
      t.string :pin_digest, null: false

      t.timestamps
    end
    add_index :users, :username, unique: true
    add_index :users, :email_address, unique: true
  end
end
