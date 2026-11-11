# Runs an engine command that prints one JSON line per event, and streams each
# event to the user's rig setup page as it happens. Subclasses say which command
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
      io = IO.popen(argv, chdir: EngineRunner.engine_dir.to_s, err: File::NULL)
      state = State.new(kind:, label:, user_id: user.id, pid: io.pid, started_at: Time.current,
                        finished: false, data: initial_data(**opts))
      RigCheck.store(state)
      Thread.new { read(io, state, user) }
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
      def read(io, state, user)
        io.each_line do |line|
          event = JSON.parse(line) rescue next
          RigCheck::MUTEX.synchronize { apply(state, event, user) }
          broadcast(user, state, event)
        end
      ensure
        io.close
        RigCheck::MUTEX.synchronize do
          state.finished = true
          state.error ||= "it stopped without reporting" unless finished_cleanly?(state)
        end
        broadcast(user, state, nil)
      end

      def push(user, target, component)
        Rails.application.executor.wrap do
          Turbo::StreamsChannel.broadcast_replace_to([ user, :setup ], target:, renderable: component, layout: false)
        end
      end
  end
end
