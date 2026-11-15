# The announcer when the shooter chose a personality (Personality): what the
# engine would say is said the personality's way, from its bank of lines
# (PersonalityBank), in its voice. The range officer always stays standard.
#
#   engine "announce" (a shot's)  held: replaced by hers once the shot event
#                                 arrives (with the shot's facts); the held one
#                                 plays if that doesn't happen within HOLD_S
#   engine "announce" (a line)    "ready", "card off"...: hers, else standard
#   engine "shot"                 the score and direction (the standard pieces,
#                                 always right), then her line: the moment (a
#                                 streak, a flyer, a tip...) or how good it was;
#                                 every 10 shots the card total her way
#   session / match end           her summary (chatty mode's is skipped)
#
# PersonalityAnnouncer.inline = true runs everything in line (specs).
class PersonalityAnnouncer
  HOLD_S = 4.0          # how long a shot's standard line waits for the shot event
  # Her lines are several short sentences: the standard 0.55 / 0.25 s pauses made a
  # long one 10-15 s, and shots 10 s apart got ahead of her (the demo, 2026-11-14).
  GAPS = { "sentence" => 0.3, "comma" => 0.15 }.freeze
  # The engine's own lines she says her way (the rest - the range officer - stay standard).
  ENGINE_LINES = { "ready" => "ready", "new card, ready" => "new card", "same card, ready" => "same card",
                   "card off" => "card off", "camera connection lost" => "camera connection lost",
                   "scoring paused" => "scoring paused", "please wait" => "please wait", "view moving" => "view moving",
                   "geometry warning, consider a fresh card" => "geometry warning" }.freeze
  FLAGS = { line_call: "flag line call", ambiguous: "flag ring uncertain", overlap: "flag overlaps a hole" }.freeze
  # The card total's lines that claim a comparison, by how the card compared (Commentary#summary_info).
  CARD_POOLS = { personal_best: [ "card_done best today", "card_done" ], best_today: [ "card_done best today", "card_done" ],
                 better: [ "card_done better", "card_done", "card_done not best" ], first: [ "card_done" ] }.freeze

  class_attribute :inline, default: false
  @held = {}
  @lock = Mutex.new
  class << self
    attr_reader :held, :lock
  end

  # The announcer for this session, when its shooter chose a personality that can run here.
  def self.for(session)
    personality = Personality.for(session.user) or return nil
    new(session, personality)
  end

  def initialize(session, personality, random: Random.new)
    @session, @personality, @random = session, personality, random
    @bank = PersonalityBank.new(personality.id, session, random:)
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
    situation = ENGINE_LINES[standard.sentences.map { it.join(", ") }.join(", ")] or return false
    line = @bank.pick(situation) or return false
    deliver(split(line), standard.kind)
    true
  end

  # After an engine "shot" event (or a shot plotted by hand): her reading of it,
  # or the engine's own (held) line when it wasn't scored.
  def shot!(shot)
    held = take_held
    if !shot.scored?
      Announcement.new(@session, held).deliver! if held
      return true
    end
    standard = held ? Announcement.new(@session, held) : Announcement.for_shot(shot)
    deliver(shot_sentences(shot), standard.kind || "ok", supersede: "shot")
    true
  end

  # The end of a practice session: said BEFORE the page reloads (so in line).
  def session_end!
    shots = commentary.shots
    return true if shots.empty?

    average = format("%.1f", shots.sum { commentary.value(it) } / shots.size.to_f)
    cards = full_series(shots)
    line = @bank.pick("session_end", shots: shots.size, avg: average, best: (number(cards.max) if cards.size > 1))
    line ? deliver(split(line), "chat") : false
  end

  def match_end!
    shots = commentary.shots
    return if shots.empty?

    series = full_series(shots)
    line = @bank.pick("match_done", total: number(shots.sum { commentary.value(it) }), best: (number(series.max) if series.size > 1))
    line ? deliver(split(line), "chat") : Commentary.new(@session).then { it.deliver!(it.after_match) }
  end

  # What she says for a scored shot, as sentences of voice pieces.
  def shot_sentences(shot)
    out = []
    out += split(@bank.pick("sighter")) if shot.sighter? && @bank.has?("sighter")
    score = [ Announcement.spoken_score(shot), Announcement.spoken_direction(shot, random: @random) ]
    score << "inner ten" if shot.final_inner_ten?
    out << score
    if shot.penalized?
      return out + split(@bank.pick("penalty #{shot.penalty}") || "#{shot.penalty}, scores zero")
    end

    n = commentary.shots.index { it.id == shot.id }&.+(1)
    summary = n && (n % Commentary::SERIES).zero?
    remark = (moment_line(shot, n) if n) || (@bank.pick(step(shot)) unless summary)
    out += split(remark) if remark
    flag = flag_line(shot)
    out += split(flag) if flag
    out += summary_lines(shot, n) if summary
    out
  end

  private
    def commentary = @commentary ||= Commentary.new(@session)
    def split(text) = Commentary.split(text.to_s)
    def number(v) = commentary.whole? ? v.to_i.to_s : format("%.1f", v)
    def words(n) = PersonalityFacts.words(n)
    def full_series(shots) = shots.each_slice(Commentary::SERIES).select { it.size == Commentary::SERIES }.map { |s| s.sum { commentary.value(it) } }

    # How good it was, in the bank's steps (the decimal, as engine/directions.json).
    def step(shot)
      return "inner" if shot.final_inner_ten?

      d = shot.final_decimal.to_f.round(1)
      if d >= 10.0 then "ten"
      elsif d >= 9.5 then "s95"
      elsif d >= 9.0 then "s90"
      elsif d >= 8.0 then "eight"
      elsif d >= 7.0 then "seven"
      else "awful"
      end
    end

    # The moment, as chatty mode sees it (Commentary#moment), plus her own: a bad
    # shot after a run of five or more in the nine or better.
    def moment_line(shot, n)
      key, values = commentary.moment(n)
      line = case key
      when :streak_tens then @bank.pick("tens_streak", n: words(values[:n]))
      when :nine_run then @bank.pick("nine_run", n: words(values[:n]))
      when :pattern then @bank.pick("tip #{values[:dir]}")
      when :flyer then @bank.pick("flyer")
      end
      return line if line || shot.final_ring.to_i >= 9

      run = commentary.shots.first(n - 1).reverse.take_while { !it.penalized? && it.final_ring.to_i >= 9 }.size
      @bank.pick("drop_after_run", n: words(run)) if run >= 5
    end

    def flag_line(shot)
      return unless @session.user.diagnostic_announcements?

      situation = FLAGS.find { |attr, _| shot.public_send(attr) }&.last
      situation ||= "flag found without a sound" if %w[ camera final_check ].include?(shot.trigger) && @session.mic.present? && @session.mic != "none"
      @bank.pick(situation) if situation
    end

    # Every 10 shots: the card (or a match's series) total her way, the match
    # milestones, and a new card in practice.
    def summary_lines(shot, n)
      info = commentary.summary_info(n)
      total = number(info[:total])
      line = if info[:series] then @bank.pick("series_done", "card_done", total:)
      else @bank.pick_any(CARD_POOLS.fetch(info[:compared].first, [ "card_done", "card_done not best" ]), total:)
      end
      out = split(line)
      out += split(@bank.pick("halfway", total: number(info[:halfway]))) if info[:halfway]
      out += split(@bank.pick("last series")) if info[:last_series]
      out += split(@bank.pick("new card please")) if @session.course.blank? && shot.number == (@session.per_card || 10)
      out
    end

    def deliver(sentences, kind, supersede: nil)
      sentences = sentences.reject(&:empty?)
      return false if sentences.empty?

      Announcement.new(@session, { "kind" => kind, "plain_kind" => kind, "gaps" => GAPS, "supersede" => supersede,
                                   "sentences" => sentences.map { { "pieces" => it } } }).deliver!
      true
    end

    # A shot's announcement leads with its number ("shot 4") or "sighter"
    # (phase1.py: lead = "sighter" / f"shot {n}").
    def shot_line?(data)
      first = Array(data.dig("sentences", 0, "pieces")).first.to_s
      first.match?(/\Ashot \d+\z/) || first == "sighter"
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
