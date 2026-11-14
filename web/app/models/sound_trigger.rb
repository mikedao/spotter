# The engine's sound trigger rule, for the parts of the web app that judge sounds
# themselves - the BROWSER's sound check and the range screen's browser trigger
# (lib/shot_listener.js): a sound counts as a shot at DB over the room's floor
# and MS long. engine/phase1.py's TRIGGER_DB / TRIGGER_MS; spec/models/
# sound_trigger_spec.rb fails when the two drift apart. A remembered sound check
# counts only if it passed at these values (User#sound_checked?).
module SoundTrigger
  DB = 62.0
  MS = 180.0
  # Sounds this close below DB are sent to the engine anyway: it logs near misses,
  # so a quiet real shot shows in the log.
  NEAR_DB = 12.0

  def self.would_trigger?(over_db, len_ms) = over_db.to_f >= DB && len_ms.to_f >= MS
end
