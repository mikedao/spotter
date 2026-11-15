require "net/http"

# Announcer personalities (Settings, "Personalities"): a voice plus a small
# language model fine-tuned to talk like a character, run on this computer by
# the engine's voice helper (../engine/voice/talk.py, personalities/<id>.py).
# With one chosen, the announcer says everything in its words - the score and
# direction its way, the moments, the engine's lines - and in its voice; the
# range officer stays standard. Anything it can't say in time, or that fails its
# checks, is said the standard way instead (PersonalityAnnouncer).
#
# ALL mirrors the engine's personalities/*.py (spec/models/personality_spec.rb).
#
#   Personality.for(user)         # the chosen one, or nil
#   Personality.ensure!("katey")  # start its process in the background (idempotent)
#   Personality.say("katey", facts)  # => { "ok" => true, "sentences" => [[...]] } or nil
class Personality
  Entry = Data.define(:id, :name, :voice, :description)

  ALL = {
    "katey" => Entry.new(id: "katey", name: "Katey", voice: "af_nicole",
                         description: "Mean girl. Queen bee, unimpressed, roasts your bad shots. Swears.")
  }.freeze

  class << self
    def all = ALL.values
    def find(id) = ALL[id.to_s]
    def valid?(id) = ALL.key?(id.to_s)

    # The user's personality, when it can actually run here (its bank of lines and
    # the voices are here).
    def for(user)
      entry = find(user&.personality)
      entry if entry && ready?(entry.id)
    end

    def ready?(id) = PersonalityBank.available?(id) && Voice.available?

    def dir(id) = Voice.dir.join("cache", "talk", id.to_s)
    def trained?(id) = dir(id).join("adapter", "adapters.safetensors").exist? && Voice.available?

    # ---- its process: 127.0.0.1 only; one per personality, kept running ------------
    def state_file(id) = Rails.root.join("tmp", "personality-#{id}.json")
    def log_file(id) = Rails.root.join("log", "personality-#{id}.log")

    # Start it unless it runs already (a few seconds to load; then it renders its
    # likely voice pieces in the background, on 2 cores).
    def ensure!(id)
      return unless valid?(id) && trained?(id)
      return if alive?(id)

      port = EngineRunner.free_port
      pid = Process.spawn(Voice.render_env.merge("PYTHONUNBUFFERED" => "1"),
                          Voice.python.to_s, "talk.py", "serve", "--personality", id.to_s, "--port", port.to_s,
                          chdir: Voice.dir.to_s, out: [ log_file(id).to_s, "a" ], err: [ :child, :out ], pgroup: true)
      Process.detach(pid)
      state_file(id).write({ pid:, port: }.to_json)
    end

    def stop!(id)
      pid = state["pid"] if (state = read_state(id))
      Process.kill("TERM", -pid) if pid
    rescue Errno::ESRCH, Errno::EPERM
      nil
    ensure
      state_file(id).delete if state_file(id).exist?
    end

    # Its process exists (it may still be loading).
    def alive?(id)
      pid = read_state(id)&.dig("pid")
      return false unless pid

      Process.kill(0, pid)
      true
    rescue Errno::ESRCH, Errno::EPERM
      false
    end

    # { "ready", "prepared", "of" } once it answers, else nil.
    def health(id) = request(id, Net::HTTP::Get.new("/health"), timeout: 0.5)

    # Her line for these facts (PersonalityFacts), its pieces rendered: { "ok",
    # "text", "sentences" }, or nil when she isn't running or took too long.
    def say(id, facts, budget_s: 2.5)
      post = Net::HTTP::Post.new("/say", "Content-Type" => "application/json")
      post.body = { facts:, budget_s: }.to_json
      request(id, post, timeout: budget_s + 2.5)
    end

    private
      def read_state(id) = (JSON.parse(state_file(id).read) if state_file(id).exist?)

      def request(id, req, timeout:)
        port = read_state(id)&.dig("port") or return nil
        Net::HTTP.start("127.0.0.1", port, open_timeout: 0.3, read_timeout: timeout) { JSON.parse(it.request(req).body) }
      rescue StandardError
        nil
      end
  end
end
