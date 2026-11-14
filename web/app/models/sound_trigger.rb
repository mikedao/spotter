# The engine's sound trigger rule, for the parts of the web app that judge sounds
# themselves - the sound checks and the range screen's browser trigger
# (lib/shot_listener.js): a sound counts as a shot at a LEVEL over the room's
# floor and MS long. DB / MS are engine/phase1.py's TRIGGER_DB / TRIGGER_MS
# (spec/models/sound_trigger_spec.rb fails when they drift apart).
#
# The level is PER MICROPHONE (2026-11-13: the laptop's browser heard some shots
# at +58..+62 dB, under the fixed +62): set in the sound check, kept in
# users.trigger_levels {mic => dB}, recorded on each session (trigger_db) and
# passed to the engine as --trigger-db. DB is the level until one is set. A
# remembered sound check counts only at the mic's current level.
module SoundTrigger
  DB = 62.0
  MS = 180.0
  LEVELS = (40.0..80.0)
  # Sounds this close below the level are sent to the engine anyway: it logs near
  # misses, so a quiet real shot shows in the log.
  NEAR_DB = 12.0

  def self.level(user, mic) = user.trigger_levels.to_h[mic.to_s]&.to_f || DB

  def self.set_level!(user, mic, db)
    db = db.to_f.round.to_f.clamp(LEVELS)
    user.update!(trigger_levels: user.trigger_levels.to_h.merge(mic.to_s => db))
    db
  end

  def self.would_trigger?(over_db, len_ms, level: DB) = over_db.to_f >= level && len_ms.to_f >= MS
end
