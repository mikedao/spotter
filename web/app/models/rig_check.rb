# Rig setup checks: the live camera check and the sound check. They use the same
# camera and microphone as a practice session, so only one runs at a time and
# never during a session. Each user sees only their own; the last result of each
# kind is kept (in this process) for the page to show.
module RigCheck
  class Busy < StandardError; end

  MUTEX = Mutex.new
  @states = {}

  class << self
    def ensure_free!
      if (running = EngineRunner.running)
        raise Busy, "#{running.user.name} is shooting - the camera and microphone are in use"
      end
      if (busy = running_check)
        raise Busy, "a #{busy.label} is running"
      end
    end

    def store(state) = MUTEX.synchronize { @states[[ state.kind, state.user_id ]] = state }
    def state(kind, user) = MUTEX.synchronize { @states[[ kind, user.id ]] }
    def running_check = MUTEX.synchronize { @states.values.find(&:running?) }

    # Forget every check's state (specs: it lives in the process, across examples).
    def reset! = MUTEX.synchronize { @states.clear }

    # Stop running checks (SIGINT = Ctrl+C). Run when the web app exits: a check's
    # state lives only in this process, so after a restart nothing could stop a
    # check left running, and it would hold the camera or microphone for minutes.
    def stop_all!
      MUTEX.synchronize { @states.values.select(&:running?) }.each do |state|
        Process.kill("INT", state.pid)
      rescue Errno::ESRCH
        nil
      end
    end
  end

  at_exit { stop_all! }
end
