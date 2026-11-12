# The announcer voices: Kokoro text-to-speech, run by the engine's helper
# (../engine/voice/speak.py, on its own Python 3.13). Each shooter picks one on
# Settings (users.voice); EngineRunner starts the engine with it, and the
# engine speaks every announcement in it, with pauses between its pieces.
#
# ALL mirrors the engine's voicelines.VOICES (spec/models/voice_spec.rb checks
# they match). When Kokoro isn't set up (engine/voice/setup.sh), the engine
# uses the Mac voice and the picker says so.
#
#   Voice.for(user)            # the user's voice, or the default
#   Voice.sample_path("af_heart")   # a WAV of it reading the sample lines
class Voice
  Entry = Data.define(:id, :name, :accent, :gender) do
    def label = "#{name} · #{accent} #{gender}"
  end

  ALL = {
    "af_heart" => [ "Heart", "American", "female" ], "af_alloy" => [ "Alloy", "American", "female" ],
    "af_aoede" => [ "Aoede", "American", "female" ], "af_bella" => [ "Bella", "American", "female" ],
    "af_nicole" => [ "Nicole", "American", "female" ], "af_nova" => [ "Nova", "American", "female" ],
    "af_sarah" => [ "Sarah", "American", "female" ], "af_sky" => [ "Sky", "American", "female" ],
    "am_adam" => [ "Adam", "American", "male" ], "am_fenrir" => [ "Fenrir", "American", "male" ],
    "am_michael" => [ "Michael", "American", "male" ], "am_santa" => [ "Santa", "American", "male" ],
    "bf_alice" => [ "Alice", "British", "female" ], "bf_emma" => [ "Emma", "British", "female" ],
    "bf_isabella" => [ "Isabella", "British", "female" ], "bf_lily" => [ "Lily", "British", "female" ],
    "bm_daniel" => [ "Daniel", "British", "male" ], "bm_fable" => [ "Fable", "British", "male" ],
    "bm_george" => [ "George", "British", "male" ]
  }.to_h { |id, (name, accent, gender)| [ id, Entry.new(id:, name:, accent:, gender:) ] }.freeze
  DEFAULT = "af_heart"
  # Chatty mode's lines in one voice: how many play at once (Voice.chatty_readiness).
  ChattyReadiness = Data.define(:ready, :total) do
    def complete? = ready >= total
    def missing = total - ready
    def minutes_left = (missing * 0.6 / 60).ceil   # ~0.6 s a piece, measured 2026-11-12
  end
  SAMPLE_TIMEOUT = 90

  class Failed < StandardError; end

  class << self
    def all = ALL.values
    def find(id) = ALL[id.to_s]
    def valid?(id) = ALL.key?(id.to_s)
    def for(user) = find(user&.voice) || find(DEFAULT)

    def dir = EngineRunner.engine_dir.join("voice")
    def python = dir.join(".venv", "bin", "python")
    # The web app's audio: rendered pieces (not in git, storage/) and the picker's
    # samples (in git, public/). The renderer (speak.py) is told where to write.
    def cache = Pathname(ENV.fetch("SPOTTER_VOICE_CACHE", Rails.root.join("storage", "voices").to_s))
    def samples_dir = Rails.root.join("public", "voice-samples")
    def exported_dir = Rails.root.join("public", "voice-pieces")   # every known piece, every voice, in git
    def render_env = { "SPOTTER_VOICE_CACHE" => cache.to_s, "SPOTTER_VOICE_SAMPLES" => samples_dir.to_s,
                       "SPOTTER_VOICE_PIECES" => exported_dir.to_s }
    def available? = python.exist? && dir.join("models", "kokoro-v1.0.onnx").exist?

    # The voice reading the sample lines, made on first request (~20 s for a new
    # voice; `speak.py samples` makes them all ahead of time).
    def sample_path(id)
      raise ArgumentError, "unknown voice" unless valid?(id)

      committed = samples_dir.join("#{id}.m4a")   # in git (32 kbps AAC): a fresh clone can audition every voice
      return committed if committed.exist?

      path = cache.join(id.to_s, "sample.wav")
      return path if path.exist?
      raise Failed, "the voice isn't set up (engine/voice/setup.sh)" unless available?

      _out, err, status = Timeout.timeout(SAMPLE_TIMEOUT) do
        Open3.capture3(render_env, python.to_s, "speak.py", "sample", "--voice", id.to_s, chdir: dir.to_s)
      end
      raise Failed, (err.lines.grep_v(/Warning/).last || "speak.py failed").strip unless status.success? && path.exist?

      path
    rescue Timeout::Error
      raise Failed, "making the sample took over #{SAMPLE_TIMEOUT} s"
    end

    # One voice piece ("shot 4", "9.6") as a WAV: the cached one, or rendered now
    # (~1-3 s, once; then cached for good). The cache file is named the way
    # speak.py names it. Raises Failed when it can't be made.
    PIECE = /\A[a-z0-9][a-z0-9 .,'-]{0,79}\z/

    def slug(text) = text.gsub(/[^[:alnum:]]/, "_")   # as speak.py names its files
    def piece_path(id, text) = cache.join(id.to_s, "pieces", "#{slug(text)}.wav")
    def exported_path(id, text) = exported_dir.join(id.to_s, "#{slug(text)}.m4a")

    # Where the browser gets a piece: the exported file (static, in git) when the
    # engine's known set has it, else the server, which renders it on first use.
    def piece_url(id, text)
      if exported_path(id, text).exist? then "/voice-pieces/#{id}/#{slug(text)}.m4a"
      else Rails.application.routes.url_helpers.voice_piece_path(id, text:)
      end
    end

    def piece!(id, text)
      raise ArgumentError, "unknown voice" unless valid?(id)
      raise ArgumentError, "not a voice piece" unless text.to_s.match?(PIECE)

      return exported_path(id, text) if exported_path(id, text).exist?

      path = piece_path(id, text)
      return path if path.exist?
      raise Failed, "the voice isn't set up (engine/voice/setup.sh)" unless available?

      _out, err, status = Timeout.timeout(SAMPLE_TIMEOUT) do
        Open3.capture3(render_env, python.to_s, "speak.py", "piece", "--voice", id.to_s, text.to_s, chdir: dir.to_s)
      end
      raise Failed, (err.lines.grep_v(/Warning/).last || "speak.py failed").strip unless status.success? && path.exist?

      path
    rescue Timeout::Error
      raise Failed, "rendering took over #{SAMPLE_TIMEOUT} s"
    end

    # Render every piece the engine can say in this voice, in the background
    # (~5 min), so the first session in it speaks without delays.
    # extra: more pieces to have ready (the commentary's lines and numbers).
    def prewarm!(id, extra: [])
      return unless valid?(id) && available?
      return if preparing?(id)   # one render per voice at a time

      list = nil
      if extra.any?
        list = Rails.root.join("tmp", "voice-prewarm-#{id}-#{SecureRandom.hex(4)}.txt")
        list.write(extra.join("\n"))
      end
      pid = Process.spawn(render_env, "nice", "-n", "10", python.to_s, "speak.py", "prewarm", "--voice", id.to_s,
                          *([ "--extra", list.to_s ] if list), chdir: dir.to_s, out: File::NULL, err: File::NULL, pgroup: true)
      pid_file(id).dirname.mkpath
      pid_file(id).write(pid.to_s)
      Process.detach(pid)
    end

    # A prewarm for this voice still running (Settings shows it as "preparing").
    def preparing?(id)
      pid = pid_file(id).read.to_i if pid_file(id).exist?
      return false unless pid&.positive?

      Process.kill(0, pid)
      true
    rescue Errno::ESRCH, Errno::EPERM
      pid_file(id).delete if pid_file(id).exist?
      false
    end
    def pid_file(id) = cache.join(id.to_s, "prewarm.pid")

    # Chatty mode's lines in this voice: how many can play at once (exported in
    # git, or already rendered) of all it can say. The rest are rendered the
    # first time they are said, which delays that remark by a second or more.
    def chatty_readiness(id, pieces)
      ChattyReadiness.new(ready: pieces.count { exported_path(id, it).exist? || piece_path(id, it).exist? }, total: pieces.size)
    end
    # Voices whose chatty lines are all in git (speak.py export --chatty): instant for everyone.
    def chatty_built_in?(id, pieces) = pieces.all? { exported_path(id, it).exist? }
  end
end
