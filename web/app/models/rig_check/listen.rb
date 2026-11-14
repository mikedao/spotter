# The sound check: runs the engine's `listen --json` on the chosen microphone and
# streams it to the page - a live level meter a few times a second, and each
# sound marked with whether it would trigger a capture at the engine's own
# settings - so the trigger can be checked by firing a few shots.
#
#   RigCheck::Listen.start!(user:, mic: "Razer Kiyo", seconds: 60)
#   RigCheck::Listen.stop!(user)          # = Ctrl+C: it reports its summary and ends
class RigCheck::Listen < RigCheck::LiveProcess
  MAX_SECONDS = 300

  class << self
    def label = "sound check"

    def command(user:, mic:, seconds:, **)
      mic = mic.to_s.strip
      raise EngineRunner::BadCamera, "pick a microphone" if mic.empty? || mic == CameraProbe::NO_MIC
      raise EngineRunner::BadCamera, "that isn't a microphone name" unless EngineRunner.valid_mic?(mic)

      [ EngineRunner.python, "phase1.py", "listen", "--json", "--mic=#{mic}",
        "--seconds", seconds.to_i.clamp(5, MAX_SECONDS).to_s ]
    end

    def initial_data(mic:, seconds:, level: SoundTrigger::DB)
      { "mic" => mic.to_s.strip, "seconds" => seconds.to_i, "sounds" => [], "level" => level }
    end

    # The trigger level changed in the middle of a check: judge by the new one.
    def set_level(user, db)
      state = state_for(user)
      RigCheck::MUTEX.synchronize { state.data["level"] = db } if state
      state
    end

    def apply(state, event, _user)
      d = state.data
      case event["type"]
      when "start" then d.merge!("trigger_db" => event["trigger_db"], "trigger_ms" => event["trigger_ms"])
      when "level" then d["meter"] = event
      when "sound" then d["sounds"] << event
      when "error" then state.error = event["message"]
      when "end" then d["summary"] = event
      end
    end

    def finished_cleanly?(state) = state.data["summary"]

    # The meter alone a few times a second; the whole panel when anything else changes.
    def broadcast(user, state, event)
      if event&.dig("type") == "level"
        push(user, "listen_meter", ListenMeterComponent.new(state:))
      else
        push(user, "listen_panel", ListenPanelComponent.new(state:, user:))
      end
    end
  end
end
