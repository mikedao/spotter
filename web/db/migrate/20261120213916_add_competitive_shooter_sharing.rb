# Posting sessions to CompetitiveShooter.org's feed (its API, 2026-11-20): the
# member's API key from their profile there, the colorway they last posted in,
# and each post made, so a session can say "posted" and link to it.
class AddCompetitiveShooterSharing < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :cso_api_key, :string
    add_column :users, :share_colors, :string

    create_table :shared_posts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :post_id, null: false      # CompetitiveShooter.org's public id, for the link and DELETE
      t.string :url, null: false
      t.json :session_ids, default: [], null: false
      t.json :pictures, default: [], null: false
      t.timestamps
    end
  end
end
