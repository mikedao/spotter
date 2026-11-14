# The announcer when the shooter chose a personality (Personality): what the
# engine would say goes to the personality first, in its own words and voice;
# the standard announcement plays whenever it can't (not running, too slow, a
# line that failed its checks). The range officer always stays standard.
#
#   engine "announce" (a shot's)  held: its line is written once the shot event
#                                 arrives (with the shot's facts); the held one
#                                 plays if that doesn't happen within HOLD_S
#   engine "announce" (a line)    "ready", "card off"...: hers, else standard
#   engine "shot"                 her line for it (score, direction, moment, card total)
#   session / match end           her summary (chatty mode's is skipped)
#
# Her lines are written off the request thread (the engine's events never wait),
# except the session's end, which must go out before the page reloads into the
# summary. PersonalityAnnouncer.inline = true runs everything in line (specs).
class PersonalityAnnouncer
  HOLD_S = 4.0          # how long a shot's standard line waits for the shot event
  BUDGET_S = 2.5        # how long she may take to write a line (talk.py LIVE_BUDGET_S)
  # Her lines are many short sentences: the standard 0.55 / 0.25 s pauses made a
  # long one 10-15 s, and shots 10 s apart got ahead of her (the demo, 2026-11-14).
  GAPS = { "sentence" => 0.3, "comma" => 0.15 }.freeze

  class_attribute :inline, default: false
  @held = {}
  @lock = Mutex.new
  class << self
    attr_reader :held, :lock
  end

  # The announcer for this session, when its shooter chose a personality that can
  # run here; starts its process when it isn't running (standard lines meanwhile).
  def self.for(session)
    personality = Personality.for(session.user) or return nil
    return new(session, personality) if Personality.alive?(personality.id)

    Personality.ensure!(personality.id)
    nil
  end

  def initialize(session, personality)
    @session, @personality = session, personality
  end

  # An engine "announce" event. Returns true when handled here (the caller then
  # plays nothing itself).
  def announce!(data)
    standard = Announcement.new(@session, data)
    return false if data["kind"] == "ro" || standard.sentences.empty?

    if shot_line?(data)
      hold(data)
      return true
    end
    facts = PersonalityFacts.new(@session).for_engine_line(standard.sentences) or return false
    later { speak(facts, standard.kind) || standard.deliver! }
    true
  end

  # After an engine "shot" event (or a shot plotted by hand): her line for it, or
  # the engine's own (held) line, or the standard reading of the shot.
  def shot!(shot)
    held = take_held
    if !shot.scored?
      Announcement.new(@session, held).deliver! if held
      return true
    end
    standard = held ? Announcement.new(@session, held) : Announcement.for_shot(shot)
    facts = PersonalityFacts.new(@session).for_shot(shot)
    later { speak(facts, standard.kind || "ok", supersede: "shot") || standard.deliver! }
    true
  end

  # The end of a practice session: said BEFORE the page reloads (so in line).
  def session_end!
    facts = PersonalityFacts.new(@session).for_session_end or return true
    speak(facts, "chat")
  end

  def match_end!
    facts = PersonalityFacts.new(@session).for_match_end or return
    later { speak(facts, "chat") || Commentary.new(@session).then { it.deliver!(it.after_match) } }
  end

  private
    # A shot's announcement leads with its number ("shot 4") or "sighter"
    # (phase1.py: lead = "sighter" / f"shot {n}").
    def shot_line?(data)
      first = Array(data.dig("sentences", 0, "pieces")).first.to_s
      first.match?(/\Ashot \d+\z/) || first == "sighter"
    end

    # Her line, delivered; false when she couldn't (the caller says the standard one).
    # supersede: "shot" = a newer shot's line drops this one if it is still waiting
    # to play (the range screen's queue), so she is never more than a line behind.
    def speak(facts, kind, supersede: nil)
      reply = Personality.say(@personality.id, facts, budget_s: BUDGET_S)
      return false unless reply && reply["ok"] && reply["sentences"].present?

      Announcement.new(@session, { "kind" => kind, "plain_kind" => kind, "gaps" => GAPS, "supersede" => supersede,
                                   "sentences" => reply["sentences"].map { { "pieces" => it } } }).deliver!
      true
    end

    def hold(data)
      key = @session.id
      self.class.lock.synchronize { self.class.held[key] = data }
      return if inline                    # specs call shot! themselves
      later do
        sleep HOLD_S
        stale = self.class.lock.synchronize { self.class.held.delete(key) if self.class.held[key].equal?(data) }
        Announcement.new(@session, stale).deliver! if stale
      end
    end

    def take_held = self.class.lock.synchronize { self.class.held.delete(@session.id) }

    def later(&block)
      return block.call if inline

      Thread.new { Rails.application.executor.wrap(&block) }
    end
end
