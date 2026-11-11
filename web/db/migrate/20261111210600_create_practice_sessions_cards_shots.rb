# The spotter data model: a practice session (one run of `phase1.py shot --auto`)
# holds cards, a card holds shots.
#
# Every shot keeps the scoring rules' PROPOSAL and the shooter's CALL in separate
# columns, never overwriting one with the other. Their difference is the training
# label for the planned model that will replace the hand-written rules (the same
# split fl-shooters uses between a scorer's proposed holes and the member's final
# ones).
#
# Positions are millimetres from the target centre, x right and y UP - the
# spotter engine's convention (fl-shooters stores y down; convert at any boundary).
class CreatePracticeSessionsCardsShots < ActiveRecord::Migration[8.1]
  def change
    create_table :practice_sessions do |t|
      t.string :engine_session_id, null: false   # the engine's id for this run
      t.string :target, null: false, default: "pistol"   # TargetSpec key
      t.string :rule                              # touch rule the engine scored with
      t.string :status, null: false, default: "starting"  # live status line
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.text :notes
      t.timestamps
    end
    add_index :practice_sessions, :engine_session_id, unique: true

    create_table :cards do |t|
      t.references :practice_session, null: false, foreign_key: true
      t.integer :number, null: false              # 1, 2, ... within the session
      t.datetime :started_at, null: false
      t.timestamps
    end
    add_index :cards, [ :practice_session_id, :number ], unique: true

    create_table :shots do |t|
      t.references :card, null: false, foreign_key: true
      t.integer :number                           # on the card, 1..; nil while unscored
      t.string :engine_shot_id                    # the engine's log number, e.g. "044"
      t.string :status, null: false, default: "scored"   # scored | unscored
      t.string :unscored_reason
      t.datetime :fired_at, null: false
      t.string :trigger                           # sound | camera | final_check
      t.float :sound_db

      # --- the rules' proposal ---
      t.float :x_mm
      t.float :y_mm
      t.float :r_mm
      t.decimal :decimal_score, precision: 3, scale: 1
      t.integer :ring
      t.boolean :inner_ten, null: false, default: false
      t.string :rule
      t.float :line_mm                            # pellet-mark edge to the nearest ring line
      t.boolean :line_call, null: false, default: false
      t.boolean :ambiguous, null: false, default: false
      t.boolean :overlap, null: false, default: false
      t.json :estimates                           # centroid, circle fit, visible edge...
      t.json :region                              # detected region: dia, circularity, peak
      t.json :geometry                            # ring fit RMS, perspective, lens terms

      # --- the shooter's call (the label) ---
      t.integer :call_ring
      t.decimal :call_decimal, precision: 3, scale: 1
      t.float :call_x_mm                          # where the pellet went through, tapped
      t.float :call_y_mm
      t.text :call_note
      t.datetime :called_at

      t.timestamps
    end
    add_index :shots, [ :card_id, :number ]
    add_index :shots, :engine_shot_id
  end
end
