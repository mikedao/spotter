# Announcer personalities (Settings, "Personalities"): a character with a voice
# and a large bank of lines it picks from (PersonalityBank). With one chosen, the
# announcer says the score and direction, then the personality's take on it -
# the moments, the card totals, the engine's lines - in its voice; the range
# officer stays standard (PersonalityAnnouncer).
#
# ALL mirrors the engine's personalities/*.py (spec/models/personality_spec.rb).
#
#   Personality.for(user)   # the chosen one, when it can run here, or nil
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
  end
end
