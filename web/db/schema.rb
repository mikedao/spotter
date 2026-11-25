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

ActiveRecord::Schema[8.1].define(version: 2026_11_25_203106) do
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

  create_table "exercises", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_exercises_on_user_id"
  end

  create_table "guns", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "name", null: false
    t.string "kind", null: false
    t.string "make_model"
    t.text "notes"
    t.datetime "retired_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_guns_on_user_id"
  end

  create_table "hold_drills", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "reps", null: false
    t.integer "hold_seconds", null: false
    t.integer "rest_seconds", null: false
    t.integer "reps_done", default: 0, null: false
    t.integer "let_downs", default: 0, null: false
    t.float "held_seconds", default: 0.0, null: false
    t.integer "plan_week"
    t.integer "plan_day"
    t.datetime "performed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "performed_at"], name: "index_hold_drills_on_user_id_and_performed_at"
    t.index ["user_id"], name: "index_hold_drills_on_user_id"
  end

  create_table "pellets", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "name", null: false
    t.decimal "weight_grains", precision: 5, scale: 2
    t.decimal "head_mm", precision: 4, scale: 2
    t.string "lot"
    t.text "notes"
    t.datetime "retired_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_pellets_on_user_id"
  end

  create_table "plan_enrollments", force: :cascade do |t|
    t.integer "user_id", null: false
    t.date "started_on", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "schedule"
    t.json "match_days", default: [], null: false
    t.index ["user_id"], name: "index_plan_enrollments_on_user_id", unique: true
  end

  create_table "plan_workouts", force: :cascade do |t|
    t.integer "plan_enrollment_id", null: false
    t.integer "week", null: false
    t.integer "day", null: false
    t.datetime "completed_at"
    t.text "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "share_error"
    t.index ["plan_enrollment_id", "week", "day"], name: "index_plan_workouts_on_plan_enrollment_id_and_week_and_day", unique: true
    t.index ["plan_enrollment_id"], name: "index_plan_workouts_on_plan_enrollment_id"
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
    t.string "course"
    t.json "course_state"
    t.integer "gun_id"
    t.integer "pellet_id"
    t.text "gun_adjustments"
    t.text "problems"
    t.text "fixes"
    t.text "learned"
    t.integer "break_seconds", default: 0, null: false
    t.float "trigger_db"
    t.integer "plan_week"
    t.integer "plan_day"
    t.integer "plan_block"
    t.integer "group_of"
    t.index ["engine_session_id"], name: "index_practice_sessions_on_engine_session_id", unique: true
    t.index ["gun_id"], name: "index_practice_sessions_on_gun_id"
    t.index ["pellet_id"], name: "index_practice_sessions_on_pellet_id"
    t.index ["plan_week", "plan_day"], name: "index_practice_sessions_on_plan_week_and_plan_day"
    t.index ["run_token"], name: "index_practice_sessions_on_run_token", unique: true
    t.index ["user_id"], name: "index_practice_sessions_on_user_id"
  end

  create_table "session_exercises", force: :cascade do |t|
    t.integer "practice_session_id", null: false
    t.integer "exercise_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["exercise_id"], name: "index_session_exercises_on_exercise_id"
    t.index ["practice_session_id", "exercise_id"], name: "index_session_exercises_on_practice_session_id_and_exercise_id", unique: true
    t.index ["practice_session_id"], name: "index_session_exercises_on_practice_session_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "shared_posts", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "post_id", null: false
    t.string "url", null: false
    t.json "session_ids", default: [], null: false
    t.json "pictures", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "plan_week"
    t.integer "plan_day"
    t.index ["user_id"], name: "index_shared_posts_on_user_id"
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
    t.string "stage"
    t.integer "series"
    t.integer "match_number"
    t.string "penalty"
    t.datetime "pinpointed_at"
    t.float "detect_seconds"
    t.index ["card_id", "number"], name: "index_shots_on_card_id_and_number"
    t.index ["card_id"], name: "index_shots_on_card_id"
    t.index ["engine_shot_id"], name: "index_shots_on_engine_shot_id"
  end

  create_table "slow_drills", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "shots", null: false
    t.integer "string_size", null: false
    t.integer "limit_seconds", null: false
    t.integer "between_seconds", null: false
    t.integer "string_rest_seconds", null: false
    t.integer "shots_fired", default: 0, null: false
    t.integer "let_downs", default: 0, null: false
    t.float "break_seconds", default: 0.0, null: false
    t.integer "plan_week"
    t.integer "plan_day"
    t.datetime "performed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "performed_at"], name: "index_slow_drills_on_user_id_and_performed_at"
    t.index ["user_id"], name: "index_slow_drills_on_user_id"
  end

  create_table "timed_drills", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "strings", null: false
    t.integer "shots", null: false
    t.integer "string_seconds", null: false
    t.integer "rest_seconds", null: false
    t.integer "strings_done", default: 0, null: false
    t.integer "plan_week"
    t.integer "plan_day"
    t.datetime "performed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "performed_at"], name: "index_timed_drills_on_user_id_and_performed_at"
    t.index ["user_id"], name: "index_timed_drills_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "username", null: false
    t.string "email_address", null: false
    t.string "pin_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name", default: "", null: false
    t.string "last_camera"
    t.string "last_mic"
    t.string "voice"
    t.json "goals", default: {}, null: false
    t.boolean "diagnostic_announcements", default: false, null: false
    t.boolean "chatty", default: false, null: false
    t.json "sound_check"
    t.json "trigger_levels"
    t.string "personality"
    t.string "cso_api_key"
    t.string "share_colors"
    t.string "setup_plan_block"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "cards", "practice_sessions"
  add_foreign_key "exercises", "users"
  add_foreign_key "guns", "users"
  add_foreign_key "hold_drills", "users"
  add_foreign_key "pellets", "users"
  add_foreign_key "plan_enrollments", "users"
  add_foreign_key "plan_workouts", "plan_enrollments"
  add_foreign_key "practice_sessions", "guns"
  add_foreign_key "practice_sessions", "pellets"
  add_foreign_key "practice_sessions", "users"
  add_foreign_key "session_exercises", "exercises"
  add_foreign_key "session_exercises", "practice_sessions"
  add_foreign_key "sessions", "users"
  add_foreign_key "shared_posts", "users"
  add_foreign_key "shots", "cards"
  add_foreign_key "slow_drills", "users"
  add_foreign_key "timed_drills", "users"
end
