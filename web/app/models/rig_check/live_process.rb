# Runs an engine command that prints one JSON line per event, and streams each
# event to the user's setup wizard page as it happens. Subclasses say which command
# (`command`), how an event changes their state (`apply`), and what to redraw
# (`broadcast`). Stop = SIGINT = Ctrl+C: the engine ends cleanly and reports.
class RigCheck::LiveProcess
  State = Struct.new(:kind, :label, :user_id, :pid, :started_at, :finished, :error, :data, keyword_init: true) do
    def running? = !finished && RigCheck::LiveProcess.alive?(pid)
  end

  class << self
    def start!(user:, **opts)
      RigCheck.ensure_free!
      argv = command(user:, **opts)
      # The engine's error output is kept (log/rig_check/), so a check that dies
      # can say why instead of just "it stopped" (2026-11-12: one did, mid-watch
      # on the Pi stream, and there was nothing to go on).
      log = Rails.root.join("log", "rig_check", "#{kind}-#{user.id}.log")
      log.dirname.mkpath
      io = IO.popen(argv, chdir: EngineRunner.engine_dir.to_s, err: [ log.to_s, "w" ])
      state = State.new(kind:, label:, user_id: user.id, pid: io.pid, started_at: Time.current,
                        finished: false, data: initial_data(**opts))
      RigCheck.store(state)
      Thread.new { read(io, state, user, log) }
      broadcast(user, state, nil)
      state
    end

    def stop!(user)
      state = state_for(user)
      Process.kill("INT", state.pid) if state&.running?
    end

    def state_for(user) = RigCheck.state(kind, user)
    def running?(user = nil) = (user ? state_for(user) : RigCheck.running_check)&.running? || false

    def alive?(pid)
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH, Errno::EPERM, TypeError
      false
    end

    def kind = name.demodulize.underscore.to_sym

    private
      def read(io, state, user, log = nil)
        io.each_line do |line|
          event = JSON.parse(line) rescue next
          RigCheck::MUTEX.synchronize { apply(state, event, user) }
          broadcast(user, state, event)
        end
      ensure
        io.close
        status = $?
        RigCheck::MUTEX.synchronize do
          state.finished = true
          state.error ||= stopped_message(status, log) unless finished_cleanly?(state)
        end
        broadcast(user, state, nil)
      end

      # Why a check ended without its final report: how the process ended, and
      # the last thing it printed as an error (Python's own last line).
      def stopped_message(status, log)
        how = if status&.signaled? then "it crashed (#{Signal.signame(status.termsig).then { "SIG#{it}" }})"
        elsif status && !status.success? then "it stopped with an error (exit #{status.exitstatus})"
        else "it stopped without reporting"
        end
        last = log&.file? && log.readlines.map(&:strip).reject { it.empty? || it.match?(/warning/i) }.last
        last ? "#{how}: #{last.truncate(200)}" : how
      end

      # Morphed, not swapped: only what changed is touched, so the camera
      # check's picture keeps showing the last frame until the next has loaded
      # (a swapped <img> starts empty every second: flicker and the page jumping).
      def push(user, target, component)
        Rails.application.executor.wrap do
          Turbo::StreamsChannel.broadcast_replace_to([ user, :setup ], target:, renderable: component, layout: false,
                                                     attributes: { method: :morph })
        end
      end
  end
end
