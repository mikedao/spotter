# The sound check's live meter, redrawn a few times a second: what phase it is in,
# time left, and how loud it is right now against the room's floor, with a mark
# at the trigger threshold - so a working microphone shows before any shot.
class ListenMeterComponent < ApplicationComponent
  def initialize(state:) = @state = state

  def data = @state&.data || {}
  def level = data["meter"]
  # the mic's trigger level (SoundTrigger.level), else the engine's
  def trigger = (data["level"] || data["trigger_db"]).to_f.nonzero? || SoundTrigger::DB
  def scale_max = trigger * 1.4

  def phase
    return "Starting the microphone…" unless level
    return "Measuring the room - stay quiet" unless level["floor_dbfs"]

    "Listening - fire when ready · #{level['remaining']} s left"
  end

  def bar_pct = level&.dig("over_db") ? (level["over_db"].clamp(0, scale_max) / scale_max * 100).round : 0
  def trigger_pct = (trigger / scale_max * 100).round
  def hot? = level&.dig("over_db").to_f >= trigger
end
