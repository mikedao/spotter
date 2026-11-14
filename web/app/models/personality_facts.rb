# What a personality is told before it speaks: the facts of the moment, as text,
# in EXACTLY the form its model was trained on (engine/voice/talk.py, Builder) -
# "key: value" lines, numbers as words. It may only say what these facts prove;
# talk.py's checks hold it to the score, the direction and the numbers given.
#
#   PersonalityFacts.new(session).for_shot(shot)
#   # => "event: shot\nshot: four\nscore: nine six\nhow far: nine five to nine nine\ndirection: low\n..."
#
# The moments (a streak, a pattern, a flyer, the card total and how it compares)
# come from the same rules as chatty mode (Commentary#moment, #summary_info). The
# extras (the previous shot, the card's average, the time of day, how long, tens
# today) are given only now and then, as in training, so she doesn't mention
# them after every shot.
class PersonalityFacts
  ONES = %w[ zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen
             sixteen seventeen eighteen nineteen ].freeze
  TENS = %w[ _ _ twenty thirty forty fifty sixty seventy eighty ninety ].freeze
  # How far out, by the decimal score (engine/directions.json's steps, as talk.py words them).
  STEPS = [ [ 10.0, "a ten, not an inner ten" ], [ 9.5, "nine five to nine nine" ], [ 9.0, "nine to nine four" ],
            [ 8.0, "an eight" ], [ 7.0, "a seven" ], [ 6.0, "a six" ], [ 0.0, "five or worse" ] ].freeze
  FLAGS = { line_call: "line call", ambiguous: "ring uncertain", overlap: "overlaps a hole" }.freeze
  # The engine's own lines she says her way (the rest - the range officer - stay standard).
  ENGINE_LINES = { "ready" => "ready", "new card, ready" => "new card", "same card, ready" => "same card",
                   "card off" => "card off", "camera connection lost" => "camera connection lost",
                   "scoring paused" => "scoring paused", "please wait" => "please wait", "view moving" => "view moving",
                   "geometry warning, consider a fresh card" => "geometry warning" }.freeze

  # 94 -> "ninety four", 541 -> "five hundred forty one" (talk.py's words).
  def self.words(n)
    n = n.to_i
    return ONES[n] if n < 20
    return TENS[n / 10] + (n % 10).then { it.zero? ? "" : " #{ONES[it]}" } if n < 100

    "#{ONES[n / 100]} hundred" + (n % 100).then { it.zero? ? "" : " #{words(it)}" }
  end

  # 9.6 -> "nine six", 10.0 -> "ten oh" (talk.py's decimal_words, the form she is given).
  def self.decimal_words(d)
    whole, tenth = (d.to_f * 10).round.divmod(10)
    "#{words(whole)} #{tenth.zero? ? 'oh' : ONES[tenth]}"
  end

  # A total: whole rings as words, a decimal total with "point" (104.5 -> "one hundred four point five").
  def self.total_words(v)
    whole, tenth = (v.to_f * 10).round.divmod(10)
    tenth.zero? ? words(whole) : "#{words(whole)} point #{ONES[tenth]}"
  end

  def initialize(session, random: Random.new, now: Time.zone.now)
    @session, @random, @now = session, random, now
    @commentary = Commentary.new(session)
  end

  def for_shot(shot)
    facts = { "shot" => words(shot.match_number || shot.number), "score" => decimal_words(shot.final_decimal),
              "how far" => how_far(shot), "direction" => shot.direction || "center" }
    facts["sighter"] = "yes" if shot.sighter?
    facts["penalty"] = "#{shot.penalty}, scores zero" if shot.penalized?
    n = @commentary.shots.index { it.id == shot.id }&.+(1)
    extras(facts, shot, n)
    moment(facts, shot, n) if n && !shot.penalized?
    facts["flag"] = flag(shot) if flag(shot)
    summary(facts, shot, n) if n && (n % Commentary::SERIES).zero?
    text("shot", facts)
  end

  # An engine line ("card off") as her event, or nil when it isn't one of hers.
  def for_engine_line(sentences)
    key = ENGINE_LINES[sentences.map { it.join(", ") }.join(", ")]
    key && text(key, {})
  end

  def for_session_end
    shots = @commentary.shots
    return if shots.empty?

    average = shots.sum { @commentary.value(it) } / shots.size.to_f
    facts = { "shots" => words(shots.size), "average" => decimal_words(average) }
    cards = shots.each_slice(Commentary::SERIES).select { it.size == Commentary::SERIES }
    facts["best card"] = self.class.total_words(cards.map { |c| c.sum { @commentary.value(it) } }.max) if cards.size > 1
    text("session over", facts)
  end

  def for_match_end
    shots = @commentary.shots
    return if shots.empty?

    series = shots.each_slice(Commentary::SERIES).select { it.size == Commentary::SERIES }.map { |c| c.sum { @commentary.value(it) } }
    facts = { "final score" => self.class.total_words(shots.sum { @commentary.value(it) }) }
    facts["best series"] = self.class.total_words(series.max) if series.size > 1
    text("match over", facts)
  end

  private
    def words(n) = self.class.words(n)
    def decimal_words(d) = self.class.decimal_words(d)
    def text(event, facts) = ([ "event: #{event}" ] + facts.map { |k, v| "#{k}: #{v}" }).join("\n")

    def how_far(shot)
      return "inner ten" if shot.final_inner_ten?

      d = shot.final_decimal.to_f.round(1)
      STEPS.find { d >= it[0] }[1]
    end

    def flag(shot)
      return unless @session.user.diagnostic_announcements?

      FLAGS.each { |attr, text| return text if shot.public_send(attr) }
      "found without a sound" if %w[ camera final_check ].include?(shot.trigger) && @session.mic.present? && @session.mic != "none"
    end

    # The shot before, the card so far, the time, how long, tens today - each now
    # and then (as in training: 50%, 60%, 30%, 30%, 15%, 30%).
    def extras(facts, shot, n)
      previous = n && n > 1 ? @commentary.shots[n - 2] : nil
      facts["previous"] = decimal_words(previous.final_decimal) if previous && chance(0.5)
      on_card = shot.card.shots.where(status: "scored").where(number: ..shot.number).order(:number).to_a
      per_card = @session.per_card || 10
      if shot.number == 1 && chance(0.6) then facts["card shot"] = "first"
      elsif shot.number == per_card - 1 && chance(0.6) then facts["card shot"] = "nine of ten"
      elsif on_card.size >= 3 && shot.number < per_card && chance(0.3)
        facts["card average"] = decimal_words(on_card.sum { it.final_decimal.to_f } / on_card.size)
      end
      facts["time"] = time_of_day if chance(0.3)
      minutes = (@session.shooting_seconds / 600.0).round * 10
      facts["shooting for"] = duration(minutes) if minutes >= 40 && chance(0.15)
      if shot.final_ring.to_i >= 10 && chance(0.3)
        tens = @commentary.shots.first(n || 0).count { !it.penalized? && it.final_ring.to_i >= 10 }
        facts["tens today"] = words(tens) if tens >= 2
      end
    end

    def moment(facts, shot, n)
      key, values = @commentary.moment(n)
      case key
      when :streak_tens then facts["moment"] = "#{words(values[:n])} tens in a row"
      when :nine_run then facts["moment"] = "#{words(values[:n])} in a row in the nine or better"
      when :pattern
        facts["moment"] = "third in a row #{values[:dir]}"
        facts["tip"] = "yes"
      when :flyer then facts["moment"] = "a flyer, well away from the group"
      end
      return if facts["moment"] || shot.final_ring.to_i >= 9

      # a bad shot after a run of good ones (her own moment; chatty mode has none)
      run = @commentary.shots.first(n - 1).reverse.take_while { !it.penalized? && it.final_ring.to_i >= 9 }.size
      facts["moment"] = "after #{words(run)} in a row in the nine or better" if run >= 5
    end

    def summary(facts, shot, n)
      info = @commentary.summary_info(n)
      facts[info[:series] ? "series" : "card"] = "done, total #{self.class.total_words(info[:total])}"
      kind, d = info[:compared]
      facts["compared"] = { personal_best: "personal best", best_today: "best today", first: "first today",
                            same: "same as the last" }[kind] ||
                          "#{self.class.total_words(d)} #{kind == :better ? 'better' : 'worse'} than the last"
      facts["new card"] = "yes" if @session.course.blank? && shot.number == (@session.per_card || 10)
      facts["halfway"] = "thirty shots, total #{self.class.total_words(info[:halfway])}" if info[:halfway]
      facts["last series"] = "yes" if info[:last_series]
    end

    def time_of_day
      case @now.hour
      when 5..11 then "morning"
      when 12..16 then "afternoon"
      when 17..21 then "evening"
      else "late night"
      end
    end

    def duration(minutes)
      return "#{words(minutes)} minutes" if minutes < 60
      return "two hours" if minutes >= 120

      minutes == 60 ? "an hour" : "an hour #{words(minutes - 60)}"
    end

    def chance(p) = @random.rand < p
end
