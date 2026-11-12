# The shooter's equipment: guns (one type each, pistol or rifle) and pellets
# (one row per LOT, since lots of the same pellet shoot differently), both
# chosen per practice session - optional, pre-selected from the last session.
# Retired, never deleted, so old sessions keep their gun and pellets.
class CreateGunsAndPellets < ActiveRecord::Migration[8.1]
  def change
    create_table :guns do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :kind, null: false             # TargetSpec key: pistol | rifle
      t.string :make_model
      t.text :notes
      t.datetime :retired_at
      t.timestamps
    end

    create_table :pellets do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false             # brand and name, "RWS R10 Match"
      t.decimal :weight_grains, precision: 5, scale: 2
      t.decimal :head_mm, precision: 4, scale: 2
      t.string :lot
      t.text :notes
      t.datetime :retired_at
      t.timestamps
    end

    change_table :practice_sessions do |t|
      t.references :gun, foreign_key: true
      t.references :pellet, foreign_key: true
      t.text :gun_adjustments                 # "what I changed on the gun today"
    end
  end
end
