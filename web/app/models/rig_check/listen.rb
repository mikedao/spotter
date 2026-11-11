# The sound check on the rig setup page: runs the engine's `listen --json` on the
# chosen microphone and streams each sound to the page as it happens, marked with
# whether it would trigger a capture at the engine's own settings - so the trigger
# can be checked by firing a few shots, without a terminal.
#
#   RigCheck::Listen.start!(user:, mic: "Razer Kiyo", seconds: 60)
#   RigCheck::Listen.stop!(user)          # = Ctrl+C: it reports its summary and ends
#   RigCheck::Listen.state_for(user)      # what the page shows
#
# One sound check at a time (one microphone in use), never during a session.
# Its state lives in this process: fine for the one-rig web app.
class RigCheck::Listen
  MAX_SECONDS = 300

  State = Struct.new(:user_id, :pid, :mic, :seconds, :started_at, :trigger_db, :trigger_ms,
                     :sounds, :finished, :summary, :error, keyword_init: true) do
    def shots = sounds.count { it["would_trigger"] }
  end

  @mutex = Mutex.new
  @state = nil

  class << self
    def running?
      @mutex.synchronize { @state && !@state.finished && alive?(@state.pid) }
    end

    def state_for(user) = @mutex.synchronize { @state if @state&.user_id == user.id }

    def start!(user:, mic:, seconds:)
      RigCheck.ensure_free!
      mic = mic.to_s.strip
      raise EngineRunner::BadCamera, "pick a microphone" if mic.empty? || mic == CameraProbe::NO_MIC
      raise EngineRunner::BadCamera, "that isn't a microphone name" unless EngineRunner.valid_mic?(mic)

      seconds = seconds.to_i.clamp(5, MAX_SECONDS)
      io = IO.popen([ EngineRunner.python, "phase1.py", "listen", "--json", "--mic=#{mic}", "--seconds", seconds.to_s ],
                    chdir: EngineRunner.engine_dir.to_s, err: File::NULL)
      @mutex.synchronize do
        @state = State.new(user_id: user.id, pid: io.pid, mic:, seconds:, started_at: Time.current,
                           sounds: [], finished: false)
      end
      Thread.new { read(io, user) }
      broadcast(user)
    end

    def stop!(user)
      state = state_for(user)
      Process.kill("INT", state.pid) if state && !state.finished && alive?(state.pid)
    end

    private
      def alive?(pid)
        Process.kill(0, pid)
        true
      rescue Errno::ESRCH, Errno::EPERM
        false
      end

      # One JSON line per event from the engine; each updates the page.
      def read(io, user)
        io.each_line do |line|
          event = JSON.parse(line) rescue next
          @mutex.synchronize { apply(event) }
          broadcast(user)
        end
      ensure
        io.close
        @mutex.synchronize do
          @state.finished = true
          @state.error ||= "the sound check stopped without reporting" unless @state.summary
        end
        broadcast(user)
      end

      def apply(event)
        case event["type"]
        when "start" then @state.trigger_db, @state.trigger_ms = event["trigger_db"], event["trigger_ms"]
        when "sound" then @state.sounds << event
        when "error" then @state.error = event["message"]
        when "end" then @state.summary = event
        end
      end

      def broadcast(user)
        Rails.application.executor.wrap do
          Turbo::StreamsChannel.broadcast_replace_to(
            [ user, :setup ], target: "listen_panel",
            renderable: ListenPanelComponent.new(state: state_for(user), user:), layout: false
          )
        end
      end
  end
end
