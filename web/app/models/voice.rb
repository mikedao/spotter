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
    "af_jessica" => [ "Jessica", "American", "female" ], "af_kore" => [ "Kore", "American", "female" ],
    "af_nicole" => [ "Nicole", "American", "female" ], "af_nova" => [ "Nova", "American", "female" ],
    "af_river" => [ "River", "American", "female" ], "af_sarah" => [ "Sarah", "American", "female" ],
    "af_sky" => [ "Sky", "American", "female" ],
    "am_adam" => [ "Adam", "American", "male" ], "am_echo" => [ "Echo", "American", "male" ],
    "am_eric" => [ "Eric", "American", "male" ], "am_fenrir" => [ "Fenrir", "American", "male" ],
    "am_liam" => [ "Liam", "American", "male" ], "am_michael" => [ "Michael", "American", "male" ],
    "am_onyx" => [ "Onyx", "American", "male" ], "am_puck" => [ "Puck", "American", "male" ],
    "am_santa" => [ "Santa", "American", "male" ],
    "bf_alice" => [ "Alice", "British", "female" ], "bf_emma" => [ "Emma", "British", "female" ],
    "bf_isabella" => [ "Isabella", "British", "female" ], "bf_lily" => [ "Lily", "British", "female" ],
    "bm_daniel" => [ "Daniel", "British", "male" ], "bm_fable" => [ "Fable", "British", "male" ],
    "bm_george" => [ "George", "British", "male" ], "bm_lewis" => [ "Lewis", "British", "male" ]
  }.to_h { |id, (name, accent, gender)| [ id, Entry.new(id:, name:, accent:, gender:) ] }.freeze
  DEFAULT = "af_heart"
  SAMPLE_TIMEOUT = 90

  class Failed < StandardError; end

  class << self
    def all = ALL.values
    def find(id) = ALL[id.to_s]
    def valid?(id) = ALL.key?(id.to_s)
    def for(user) = find(user&.voice) || find(DEFAULT)

    def dir = EngineRunner.engine_dir.join("voice")
    def python = dir.join(".venv", "bin", "python")
    def cache = Pathname(ENV.fetch("SPOTTER_VOICE_CACHE", dir.join("cache").to_s))
    def available? = python.exist? && dir.join("models", "kokoro-v1.0.onnx").exist?

    # The voice reading the sample lines, made on first request (~20 s for a new
    # voice; `speak.py samples` makes them all ahead of time).
    def sample_path(id)
      raise ArgumentError, "unknown voice" unless valid?(id)

      path = cache.join(id.to_s, "sample.wav")
      return path if path.exist?
      raise Failed, "the voice isn't set up (engine/voice/setup.sh)" unless available?

      _out, err, status = Timeout.timeout(SAMPLE_TIMEOUT) do
        Open3.capture3(python.to_s, "speak.py", "sample", "--voice", id.to_s, chdir: dir.to_s)
      end
      raise Failed, (err.lines.grep_v(/Warning/).last || "speak.py failed").strip unless status.success? && path.exist?

      path
    rescue Timeout::Error
      raise Failed, "making the sample took over #{SAMPLE_TIMEOUT} s"
    end

    # Render every piece the engine can say in this voice, in the background
    # (~5 min), so the first session in it speaks without delays.
    def prewarm!(id)
      return unless valid?(id) && available?

      pid = Process.spawn("nice", "-n", "10", python.to_s, "speak.py", "prewarm", "--voice", id.to_s,
                          chdir: dir.to_s, out: File::NULL, err: File::NULL, pgroup: true)
      Process.detach(pid)
    end
  end
end
