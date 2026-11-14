require "net/http"
require "socket"

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
  class NotContinuable < StandardError; end

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
    # Optional rig defaults (an index or the Pi's stream URL; a microphone name),
    # pre-selected on the pickers only when the device search finds them. No
    # built-in default: the shooter picks from what this computer can see.
    def camera = ENV["SPOTTER_CAMERA"].presence

    # A camera is an OpenCV index or a stream URL - nothing else reaches the
    # engine's command line.
    CAMERA = %r{\A(\d{1,2}|(https?|rtsp)://[^\s"']+)\z}

    def valid_camera?(value) = CAMERA.match?(value.to_s)

    # A microphone is a device name (the engine matches on it), or "none" for
    # camera only. Printable, and never starting with "-" (an option).
    def valid_mic?(value) = value.to_s.match?(/\A[^-\p{Cntrl}][^\p{Cntrl}]{0,99}\z/)
    def mic = ENV["SPOTTER_MIC"].presence || CameraProbe::NO_MIC
    def web_url = ENV.fetch("SPOTTER_WEB_URL", "http://127.0.0.1:#{ENV.fetch('PORT', 3000)}")

    # The session whose engine is running now, if any (cleaning up dead ones).
    def running
      PracticeSession.where(ended_at: nil).where.not(engine_pid: nil).find_each do |session|
        reconcile!(session)
        return session if session.live?
      end
      nil
    end

    def start!(user:, target:, per_card:, camera: nil, mic: nil, course: nil, gear: {}, env: {})
      if (busy = running)
        raise Busy, busy
      end
      if (check = RigCheck.running_check)
        raise RigCheck::Busy, "#{User.find_by(id: check.user_id)&.name || "someone"}'s #{check.label} is running"
      end
      camera = camera.to_s.strip.presence || self.camera
      raise BadCamera, "pick a camera (Find cameras and microphones shows what this computer can see)" if camera.blank?
      raise BadCamera, "that isn't a camera number or a stream URL" unless valid_camera?(camera)
      mic = mic.to_s.strip.presence || self.mic
      raise BadCamera, "that isn't a microphone name" unless valid_mic?(mic)

      session = user.practice_sessions.create!(
        engine_session_id: "#{Time.current.strftime('%Y%m%d-%H%M%S')}-#{SecureRandom.hex(2)}",
        target:, per_card: per_card.presence, camera:, mic:, course: course.presence, rule: "pellet",
        status: "starting", started_at: Time.current,
        stream_port: free_port, **gear   # gun, pellet, gun_adjustments (GearParams)
      )
      user.update!(last_camera: camera, last_mic: mic)
      launch!(session, env:)
    rescue Errno::ENOENT => e
      session&.update!(status: "ended", ended_at: Time.current,
                       engine_error: "Could not start the engine: #{e.message}. Is #{python} there?")
      session
    end

    # Continue a finished practice session from today (PracticeSession#continuable?):
    # the same session, rig and gear; the engine is told the last card - its
    # number, holes and last picture - and decides from the card on the target
    # whether that card carries on or the next one starts (--resume). The time it
    # stood finished is left out of its duration.
    def continue!(session, env: {})
      if (busy = running)
        raise Busy, busy
      end
      if (check = RigCheck.running_check)
        raise RigCheck::Busy, "#{User.find_by(id: check.user_id)&.name || "someone"}'s #{check.label} is running"
      end
      raise NotContinuable, "only a finished practice session from today can be continued" unless session.continuable?

      resume = resume_file(session)
      session.regenerate_run_token   # the old engine's token is spent
      session.update!(ended_at: nil, status: "starting", engine_error: nil, stream_port: free_port,
                      break_seconds: session.break_seconds.to_i + (Time.current - session.ended_at).round)
      launch!(session, env:, extra: [ "--resume", resume.to_s ])
    rescue Errno::ENOENT => e
      session.update!(status: "ended", ended_at: Time.current,
                      engine_error: "Could not start the engine: #{e.message}. Is #{python} there?")
      session
    end

    def command(session)
      [ python, "phase1.py", "shot", "--auto",
        "--target", session.target, "--device", session.camera,
        "--mic=#{session.mic.presence || mic}",
        "--report-to", web_url, "--session-id", session.engine_session_id,
        *([ "--per-card", session.per_card.to_s ] if session.per_card),
        *([ "--course", session.course ] if session.course),
        *([ "--stream-port", session.stream_port.to_s ] if session.stream_port),
        "--announce", "web" ]   # the range screen plays the announcements (Announcement), not the engine
    end

    # The last card for --resume: its number, where its holes are (target mm),
    # and the last scored shot's after picture, so the engine can tell whether
    # that card is still on the target.
    def resume_file(session)
      card = session.cards.order(:number).last
      shots = card ? card.shots.where(status: "scored").order(:number).to_a : []
      dir = Rails.root.join("tmp", "resume")
      FileUtils.mkdir_p(dir)
      image = shots.reverse.find { it.after_image.attached? }&.after_image
      image_path = dir.join("#{session.engine_session_id}-last.png")
      image&.open { |f| FileUtils.cp(f.path, image_path) }
      path = dir.join("#{session.engine_session_id}.json")
      path.write({ card: card&.number || 1, holes: shots.map { [ it.x_mm.to_f, it.y_mm.to_f ] },
                   image: (image_path.to_s if image) }.to_json)
      path
    end

    # The engine serves the live camera picture on this port (127.0.0.1 only);
    # the range screen gets it through PracticeSessionsController#camera.
    def free_port = TCPServer.open("127.0.0.1", 0) { |s| s.addr[1] }

    # Run the engine for a session (a new one, or a continued one: its log
    # carries on). Renders what the voice will say first, so none waits.
    def launch!(session, env: {}, extra: [])
      log = Rails.root.join("log", "engine", "#{session.engine_session_id}.log")
      FileUtils.mkdir_p(log.dirname)
      pid = Process.spawn(
        { "SPOTTER_TOKEN" => session.run_token, "PYTHONUNBUFFERED" => "1" }.merge(env),
        *command(session), *extra,
        chdir: engine_dir.to_s, out: [ log.to_s, "a" ], err: [ :child, :out ], pgroup: true
      )
      session.update!(engine_pid: pid, engine_log: log.to_s)
      Voice.prewarm!(Voice.for(session.user).id, extra: Commentary.pieces(session.user))
      watch(session, pid)
      session
    end

    # The latest live picture (JPEG bytes), or nil when the engine has none to give.
    def snapshot(session)
      return unless session.live? && session.stream_port

      res = Net::HTTP.start("127.0.0.1", session.stream_port, open_timeout: 1, read_timeout: 2) do |http|
        http.get("/snapshot.jpg")
      end
      res.body if res.is_a?(Net::HTTPOK)
    rescue SystemCallError, IOError, Net::OpenTimeout, Net::ReadTimeout
      nil
    end

    # A sound the range screen's browser heard (session.mic "browser"): handed to
    # the engine's live view (POST /trigger, with the session's token), which
    # times it on the engine's clock from ago_ms. False when the engine isn't
    # there to take it.
    def trigger!(session, ago_ms:, over_db:, len_ms:)
      return false unless session.live? && session.stream_port && session.mic == CameraProbe::BROWSER_MIC

      post_to_engine(session, "/trigger", { ago_ms: ago_ms.to_f, over_db: over_db.to_f, len_ms: len_ms.to_f })
    end

    # Shots about to be DELETED in a live session (a shot, or an earlier card's):
    # the engine counted them, so without this its spoken "shot N" ran one ahead
    # of the screen (2026-11-13, the shooter), and "that's 10" came a shot early.
    # Only shots the ENGINE scored (one placed by hand it never counted), found by
    # the engine's own position; `on_card` = on the card it is scoring now,
    # `match` = counted by the range officer. Called BEFORE the delete.
    def forget!(session, shots)
      return false unless session.live? && session.stream_port && understands?(session, "forget deleted shots: POST /forget")

      current = session.current_card
      list = shots.select { it.scored? && !it.pinpointed? && it.x_mm && it.y_mm }.map do |shot|
        { x_mm: shot.x_mm, y_mm: shot.y_mm, at: shot.fired_at.to_f, on_card: shot.card_id == current&.id,
          match: shot.match_number.present? }
      end
      list.empty? || post_to_engine(session, "/forget", { shots: list })
    end

    # = Ctrl+C: the engine makes a final check, then ends the session. The header
    # says "Stopping…" meanwhile, live (LiveBroadcast), until session_ended.
    def stop!(session)
      return unless alive?(session)

      session.update!(status: "stopping")
      LiveBroadcast.new(session).call
      Process.kill("INT", session.engine_pid)
    end

    # "Start match": end a match's sighting time now (the engine's SIGUSR1).
    def start_match!(session)
      Process.kill("USR1", session.engine_pid) if alive?(session)
    end

    # "Re-find target" (the camera got bumped): the engine takes a fresh look and
    # a new baseline from the card as it sits now, then reports "ready".
    # Only to an engine that says it understands it (prints "re-find target:
    # SIGUSR2" at start): to an older one, SIGUSR2 would be fatal.
    def refind!(session)
      return false unless alive?(session) && understands_refind?(session)

      Process.kill("USR2", session.engine_pid)
      true
    end

    # "Pause scoring" (SIGTSTP) / "Resume scoring" (SIGCONT), to change cards
    # without false shots. The header changes at once (LiveBroadcast); the engine
    # confirms with "paused", then "ready" / "new_card" / "card_off" on resume.
    # Only to an engine that prints "pause scoring: SIGTSTP" at start: an older
    # one would be SUSPENDED by SIGTSTP, camera and all.
    def pause!(session)
      return false unless alive?(session) && understands_pause?(session) &&
                          !%w[ paused resuming stopping ].include?(session.status)

      session.update!(status: "paused")
      LiveBroadcast.new(session).call
      Process.kill("TSTP", session.engine_pid)
      true
    end

    def resume_scoring!(session)
      return false unless alive?(session) && session.status == "paused"

      session.update!(status: "resuming")
      LiveBroadcast.new(session).call
      Process.kill("CONT", session.engine_pid)
      true
    end

    def understands_pause?(session) = understands?(session, "pause scoring: SIGTSTP")

    def post_to_engine(session, path, data)
      res = Net::HTTP.start("127.0.0.1", session.stream_port, open_timeout: 0.5, read_timeout: 1) do |http|
        http.post(path, data.to_json, "Content-Type" => "application/json", "X-Spotter-Token" => session.run_token.to_s)
      end
      res.is_a?(Net::HTTPNoContent)
    rescue SystemCallError, IOError, Net::OpenTimeout, Net::ReadTimeout
      false
    end

    def understands?(session, line)
      log = session.engine_log.presence && Pathname(session.engine_log)
      log&.file? && log.read.include?(line)
    end

    def understands_refind?(session) = understands?(session, "re-find target: SIGUSR2")

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
