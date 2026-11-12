# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_12_002739) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "cards", force: :cascade do |t|
    t.integer "practice_session_id", null: false
    t.integer "number", null: false
    t.datetime "started_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["practice_session_id", "number"], name: "index_cards_on_practice_session_id_and_number", unique: true
    t.index ["practice_session_id"], name: "index_cards_on_practice_session_id"
  end

  create_table "practice_sessions", force: :cascade do |t|
    t.string "engine_session_id", null: false
    t.string "target", default: "pistol", null: false
    t.string "rule"
    t.string "status", default: "starting", null: false
    t.datetime "started_at", null: false
    t.datetime "ended_at"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.string "run_token"
    t.integer "per_card"
    t.integer "engine_pid"
    t.string "engine_log"
    t.text "engine_error"
    t.string "camera"
    t.string "mic"
    t.integer "stream_port"
    t.index ["engine_session_id"], name: "index_practice_sessions_on_engine_session_id", unique: true
    t.index ["run_token"], name: "index_practice_sessions_on_run_token", unique: true
    t.index ["user_id"], name: "index_practice_sessions_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "shots", force: :cascade do |t|
    t.integer "card_id", null: false
    t.integer "number"
    t.string "engine_shot_id"
    t.string "status", default: "scored", null: false
    t.string "unscored_reason"
    t.datetime "fired_at", null: false
    t.string "trigger"
    t.float "sound_db"
    t.float "x_mm"
    t.float "y_mm"
    t.float "r_mm"
    t.decimal "decimal_score", precision: 3, scale: 1
    t.integer "ring"
    t.boolean "inner_ten", default: false, null: false
    t.string "rule"
    t.float "line_mm"
    t.boolean "line_call", default: false, null: false
    t.boolean "ambiguous", default: false, null: false
    t.boolean "overlap", default: false, null: false
    t.json "estimates"
    t.json "region"
    t.json "geometry"
    t.integer "call_ring"
    t.decimal "call_decimal", precision: 3, scale: 1
    t.float "call_x_mm"
    t.float "call_y_mm"
    t.text "call_note"
    t.datetime "called_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["card_id", "number"], name: "index_shots_on_card_id_and_number"
    t.index ["card_id"], name: "index_shots_on_card_id"
    t.index ["engine_shot_id"], name: "index_shots_on_engine_shot_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name", default: "", null: false
    t.string "last_camera"
    t.string "last_mic"
    t.string "voice"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "cards", "practice_sessions"
  add_foreign_key "practice_sessions", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "shots", "cards"
end
