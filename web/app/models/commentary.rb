# The announcer's commentary in chatty mode (users.chatty): written rules, each
# with several phrasings (config/commentary/<personality>.yml), spoken in the
# shooter's voice after the score. It only says what the shots prove:
#
#   after a shot      at most ONE remark, and only when something happened - a
#                     streak of tens, a run in the nine or better, three in a row
#                     on one side, a flyer, a 7 or worse, an inner ten
#   every 10 shots    a summary: the card or series total, how it compares (best
#                     today, a personal best, up or down on the last); in a match
#                     also "halfway" and "last series". No pace or goal talk
#                     (the shooter: not wanted)
#   a match's end     the final score and the best series
#
# Competition shots only (sighters are left alone), scored as the session is
# (whole rings for pistol practice and matches, decimals otherwise), calls win.
#
#   Commentary.new(session).after_shot(shot)   # => [ [ "3 tens in a row" ] ]   sentences of pieces
#   Commentary.new(session).after_match        # => [ [ "that's the match" ], [ "final score", "553" ], ... ]
class Commentary
  SERIES = 10
  DIRECTIONS = %w[ right high\ right high high\ left left low\ left low low\ right ].freeze

  def self.lines(personality = "default")
    @lines ||= {}
    @lines[personality] ||= YAML.load_file(Rails.root.join("config", "commentary", "#{personality}.yml"))
  end

  # Push the remarks for an engine event to the range screen, when the shooter
  # has chatty mode on.
  def self.after_event(session, type:, record: nil, data: {})
    return unless session.user.chatty?

    commentary = new(session)
    sentences = case type
    when "shot" then record.is_a?(Shot) && record.scored? && !record.sighter? ? commentary.after_shot(record) : []
    when "course" then data["phase"] == "done" ? commentary.after_match : []
    else []
    end
    commentary.deliver!(sentences)
  end

  # Every piece the commentary can say for this shooter, to render ahead.
  def self.pieces(user, personality: "default")
    fill = lambda do |line|
      values = { "n" => (3..10), "d" => (1..30), "dir" => DIRECTIONS }
      keys = line.scan(/\{(\w+)\}/).flatten.uniq
      combos = keys.empty? ? [ {} ] : keys.map { |k| values.fetch(k).map { [ k, it ] } }.reduce(&:product).map { Array(it).flatten.each_slice(2).to_h }
      combos.map { |c| c.reduce(line) { |text, (k, v)| text.gsub("{#{k}}", v.to_s) } }
    end
    texts = lines(personality).values.grep(Array).flatten.flat_map { fill.(it) }
    (texts.flat_map { split(it).flatten } + (50..100).map(&:to_s)).uniq
  end

  # Text -> sentences -> pieces, as the engine's voicelines.split.
  def self.split(text)
    text.split(". ").map { |sentence| sentence.split(",").map { it.strip.delete_suffix(".").downcase.squish }.compact_blank }.reject(&:empty?)
  end

  def initialize(session, personality: "default", random: Random.new)
    @session, @lines, @random = session, self.class.lines(personality), random
  end

  def after_shot(shot)
    n = shots.index { it.id == shot.id }&.+(1) or return []
    return summary(n) if (n % SERIES).zero?

    remark(n)
  end

  def after_match
    return [] if shots.empty?

    out = [ say(:match_done), [ *say(:final_score).first, number(total(shots)) ] ]
    out << [ *say(:best_series_was).first, number(series.max) ] if series.size > 1
    out
  end

  def deliver!(sentences)
    return if sentences.blank?

    Announcement.new(@session, { "kind" => "chat", "plain_kind" => "chat",
                                 "sentences" => sentences.map { { "pieces" => it } } }).deliver!
  end

  private
    def shots = @shots ||= SessionSummary.new(@session).shots
    def whole? = @session.whole_rings?
    def value(shot) = shot.penalized? ? 0 : (whole? ? shot.final_ring.to_i : shot.final_decimal.to_f)
    def total(list) = whole? ? list.sum { value(it) } : list.sum { value(it) }.round(1)
    def number(v) = whole? ? v.to_i.to_s : format("%.1f", v)
    def series(list = shots) = list.each_slice(SERIES).select { it.size == SERIES }.map { total(it) }
    def match? = @session.course == "match"

    # One phrasing for a moment, never the same one twice running.
    def say(key, **values)
      options = Array(@lines[key.to_s])
      last = Rails.cache.read(cache_key(key))
      choices = options.size > 1 ? options - [ last ] : options
      line = choices.sample(random: @random)
      Rails.cache.write(cache_key(key), line, expires_in: 12.hours)
      text = values.reduce(line) { |t, (k, v)| t.gsub("{#{k}}", v.to_s) }
      self.class.split(text)
    end

    def cache_key(key) = "commentary/#{@session.id}/#{key}"

    # Every 10 shots: the total and how it compares; match milestones.
    # Only the shots up to the n-th count (the moment it is about).
    def summary(n)
      upto = shots.first(n)
      done = series(upto)
      this, before = done.last, done[0...-1]
      out = [ [ *say(@session.course ? :series_done : :card_done).first, number(this) ] ]
      if before.any? && this > before.max
        out << (personal_best?(this) ? say(:personal_best).first : say(:best_today).first)
      elsif before.any? && (d = (this - before.last).round(1)) != 0
        d = whole? ? d.to_i : d
        out << (d.positive? ? say(:better_than_last, d:).first : say(:worse_than_last, d: d.abs).first)
      end
      out << [ *say(:halfway).first, number(total(upto)) ] if match? && n == 30
      out += say(:last_series) if match? && n == 50
      out
    end

    # Better than every series in this shooter's earlier sessions at this target.
    def personal_best?(this)
      earlier = @session.user.practice_sessions.where(target: @session.target).where.not(id: @session.id)
                        .includes(cards: :shots).flat_map { SessionSummary.new(it).series }
      earlier.any? && this > earlier.max
    end

    # After a single shot: the most notable thing, if anything.
    def remark(n)
      shot = shots[n - 1]
      rings = shots.first(n).map { it.penalized? ? 0 : it.final_ring.to_i }
      tens = rings.reverse.take_while { it == 10 }.size
      return say(:streak_tens, n: tens) if tens >= 3

      nines = rings.reverse.take_while { it >= 9 }.size
      return say(:nine_run, n: nines) if [ 5, 10 ].include?(nines)

      last3 = shots.first(n).last(3)
      if last3.size == 3 && last3.none? { it.final_inner_ten? || it.final_ring.to_i == 10 || it.penalized? } &&
         (dirs = last3.map(&:direction).uniq).size == 1 && dirs.first.present? && dirs.first != "center"
        return say(:pattern, dir: dirs.first) + say(:pattern_advice)
      end
      return say(:flyer) if flyer?(shot, shots.first(n - 1))
      return say(:bad_shot) if !shot.penalized? && shot.final_ring.to_i <= 7
      return say(:inner_ten) if shot.final_inner_ten?

      []
    end

    # Well outside the group so far: over 2.5x the mean radius from its middle.
    def flyer?(shot, before)
      return false if before.size < 5

      stats = CardStats.new(before, @session.target_spec)
      return false unless (mr = stats.mean_radius_mm) && shot.final_x_mm

      mx, my = stats.mean_point
      Math.hypot(shot.final_x_mm - mx, shot.final_y_mm - my) > [ 2.5 * mr, @session.target_spec.step_mm * 2 ].max
    end
end
