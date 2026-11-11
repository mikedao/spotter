# Starts and stops the scoring engine (../engine, `phase1.py shot --auto`) for a
# signed-in user, so nobody needs a terminal. One rig, one camera: only one
# session can run at a time.
#
#   session = EngineRunner.start!(user:, target: "pistol", per_card: 10)
#   EngineRunner.stop!(session)
#
# The web app creates the PracticeSession first, then launches the engine with
# that session's id (--session-id) and one-time run token (SPOTTER_TOKEN): every
# event the engine posts must present it (Api::EventsController), so an engine
# can only ever write into the session it was started for.
#
# Stopping sends SIGINT - exactly Ctrl+C - so the engine runs its final check for
# an unscored hole and reports session_ended. If the engine dies instead (no
# camera, no mic...), a watcher thread notices, ends the session and shows the
# last lines of its log on the range screen; `reconcile!` does the same on page
# load for a process that vanished while the web app was down.
class EngineRunner
  class BadCamera < StandardError; end

  class Busy < StandardError
    attr_reader :session

    def initialize(session)
      @session = session
      super("#{session.user.name} is shooting")
    end
  end

  class << self
    def engine_dir = Pathname(ENV.fetch("SPOTTER_ENGINE_DIR", Rails.root.join("..", "engine").to_s)).expand_path
    def python = ENV.fetch("SPOTTER_PYTHON", engine_dir.join(".venv/bin/python").to_s)
    # The rig: the default camera (index or the Pi's stream URL), and the
    # microphone. The shooter picks the camera on the Start form.
    def camera = ENV.fetch("SPOTTER_CAMERA", "0")

    # A camera is an OpenCV index or a stream URL - nothing else reaches the
    # engine's command line.
    CAMERA = %r{\A(\d{1,2}|(https?|rtsp)://[^\s"']+)\z}

    def valid_camera?(value) = CAMERA.match?(value.to_s)

    # A microphone is a device name (the engine matches on it), or "none" for
    # camera only. Printable, and never starting with "-" (an option).
    def valid_mic?(value) = value.to_s.match?(/\A[^-\p{Cntrl}][^\p{Cntrl}]{0,99}\z/)
    def mic = ENV.fetch("SPOTTER_MIC", "Kiyo")
    def web_url = ENV.fetch("SPOTTER_WEB_URL", "http://127.0.0.1:#{ENV.fetch('PORT', 3000)}")

    # The session whose engine is running now, if any (cleaning up dead ones).
    def running
      PracticeSession.where(ended_at: nil).where.not(engine_pid: nil).find_each do |session|
        reconcile!(session)
        return session if session.live?
      end
      nil
    end

    def start!(user:, target:, per_card:, camera: nil, mic: nil)
      if (busy = running)
        raise Busy, busy
      end
      raise RigCheck::Busy, "a sound check is running - stop it on Rig setup first" if RigCheck::Listen.running?
      camera = camera.to_s.strip.presence || self.camera
      raise BadCamera, "that isn't a camera number or a stream URL" unless valid_camera?(camera)
      mic = mic.to_s.strip.presence || self.mic
      raise BadCamera, "that isn't a microphone name" unless valid_mic?(mic)

      session = user.practice_sessions.create!(
        engine_session_id: "#{Time.current.strftime('%Y%m%d-%H%M%S')}-#{SecureRandom.hex(2)}",
        target:, per_card: per_card.presence, camera:, mic:, rule: "pellet", status: "starting", started_at: Time.current
      )
      user.update!(last_camera: camera, last_mic: mic)
      log = Rails.root.join("log", "engine", "#{session.engine_session_id}.log")
      FileUtils.mkdir_p(log.dirname)

      pid = Process.spawn(
        { "SPOTTER_TOKEN" => session.run_token, "PYTHONUNBUFFERED" => "1" },
        *command(session),
        chdir: engine_dir.to_s, out: log.to_s, err: [ :child, :out ], pgroup: true
      )
      session.update!(engine_pid: pid, engine_log: log.to_s)
      watch(session, pid)
      session
    rescue Errno::ENOENT => e
      session&.update!(status: "ended", ended_at: Time.current,
                       engine_error: "Could not start the engine: #{e.message}. Is #{python} there?")
      session
    end

    def command(session)
      [ python, "phase1.py", "shot", "--auto",
        "--target", session.target, "--device", session.camera.presence || camera,
        "--mic=#{session.mic.presence || mic}",
        "--report-to", web_url, "--session-id", session.engine_session_id,
        *([ "--per-card", session.per_card.to_s ] if session.per_card) ]
    end

    def stop!(session)
      Process.kill("INT", session.engine_pid) if alive?(session)
    end

    def alive?(session)
      return false unless session.engine_pid

      Process.kill(0, session.engine_pid)
      true
    rescue Errno::ESRCH, Errno::EPERM
      false
    end

    # A live session whose engine is gone: end it, keeping the log's tail.
    def reconcile!(session)
      return if !session.live? || alive?(session)

      tail = log_tail(session)
      session.update!(status: "ended", ended_at: Time.current,
                      engine_error: (tail if tail.present? && !tail.include?("session:")))
    end

    def log_tail(session, lines: 15)
      path = session.engine_log
      return nil unless path && File.exist?(path)

      File.readlines(path).last(lines).join.strip
    end

    private
      # Notice when the engine exits (stopped, finished, or crashed) while the
      # web app is up, and update every open range screen.
      def watch(session, pid)
        Thread.new do
          Process.wait(pid)
        rescue Errno::ECHILD
          nil
        ensure
          Rails.application.executor.wrap do
            fresh = PracticeSession.find_by(id: session.id)
            if fresh
              reconcile!(fresh)
              LiveBroadcast.new(fresh.reload).call
            end
          end
        end
      end
  end
end
