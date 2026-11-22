# The sessions a post to CompetitiveShooter.org shows: one finished session, or a
# day of training the shooter picked by hand on the journal. Counted as the
# session pages count: competition shots only (sighters never count), a shot out
# of time scores 0, your calls win; whole rings for pistol practice and matches,
# decimals for rifle and finals (a set mixing the two counts whole rings).
#
#   set = ShareSet.find(Current.user, [ 12, 14 ])
#   set.total_text    # => "565"
#   set.series        # => [ #<Series label="S1" shots=[...] total=95 complete=true>, ... ]
class ShareSet
  class Invalid < StandardError; end

  MAX_SESSIONS = 20

  Series = Data.define(:label, :session, :shots, :total, :complete)
  CardShots = Data.define(:label, :shots)

  attr_reader :sessions

  def self.find(user, ids)
    ids = Array(ids).map(&:to_i).uniq
    raise Invalid, "Pick at least one session to share." if ids.empty?
    raise Invalid, "Pick at most #{MAX_SESSIONS} sessions to share at once." if ids.size > MAX_SESSIONS

    sessions = user.practice_sessions.includes(:gun, :pellet, cards: :shots).where(id: ids).order(:started_at).to_a
    raise ActiveRecord::RecordNotFound if sessions.size != ids.size   # another user's id is a 404, as everywhere

    new(sessions)
  end

  def initialize(sessions)
    @sessions = sessions
    raise Invalid, "A session can be shared once it has finished." if sessions.any?(&:live?)
    raise Invalid, "Air pistol and air rifle sessions can't go on one target: share them apart." if sessions.map(&:target).uniq.size > 1
    raise Invalid, "Nothing to share yet: no scored shots." if shots.empty?
  end

  def ids = sessions.map(&:id)
  def single? = sessions.one?
  def session = sessions.first
  def spec = session.target_spec
  def whole_rings? = sessions.any?(&:whole_rings?)

  # --- what it was --------------------------------------------------------------

  def kind_name = single? ? (session.course_info&.name || "Practice") : "Training"
  def title = "#{spec.name} · #{kind_name}"

  def date_text
    first, last = sessions.first.started_at.to_date, sessions.last.started_at.to_date
    if first == last then first.strftime("%b %-d, %Y")
    elsif first.year == last.year && first.month == last.month then "#{first.strftime('%b %-d')}–#{last.day}, #{last.year}"
    else "#{first.strftime('%b %-d')} – #{last.strftime('%b %-d, %Y')}"
    end
  end

  def meta = [ (sessions.size.to_s + " sessions" unless single?), "#{shots.size} shots" ].compact.join(" · ")

  def guns = sessions.filter_map { it.gun&.name }.uniq
  def pellets = sessions.filter_map { it.pellet&.name }.uniq
  def exercises = sessions.flat_map { it.exercises.map(&:name) }.uniq

  # --- the shots ----------------------------------------------------------------

  def shots = @shots ||= sessions.flat_map { shots_of(it) }

  def value(shot)
    return 0 if shot.penalized?

    whole_rings? ? shot.final_ring.to_i : shot.final_decimal.to_f
  end

  def value_text(shot) = whole_rings? ? value(shot).to_s : format("%.1f", value(shot))
  def inner_ten?(shot) = !shot.penalized? && shot.final_inner_ten?

  def total = round(shots.sum { value(it) })
  def total_text = number_text(total)
  def inner_tens = shots.count { inner_ten?(it) }
  def tens = shots.count { !it.penalized? && it.final_ring.to_i == 10 }
  def out_of = whole_rings? ? shots.size * 10 : nil
  def average = (round(total.to_f / shots.size, 2) if shots.any?)

  # "565-18x": ISSF writes a whole-ring total with its inner tens; decimals stand alone.
  def score_parts = whole_rings? ? [ total_text, ("-#{inner_tens}x" if inner_tens.positive?) ] : [ total_text, nil ]

  def number_text(number) = whole_rings? ? number.to_i.to_s : format("%.1f", number)

  # Every series, labelled S1, S2... across the set: a match's 10s and a final's
  # timed windows as the range officer ran them, 10 shots at a time in practice.
  # A practice session's last few shots are a series too, marked not complete.
  def series
    @series ||= begin
      n = 0
      sessions.flat_map do |s|
        groups = if s.course.present? then shots_of(s).group_by { it.series || 0 }.sort_by(&:first).map(&:last)
        else shots_of(s).each_slice(SessionSummary::SERIES).to_a
        end
        size = s.course_info&.series_size || SessionSummary::SERIES
        groups.map do |group|
          n += 1
          complete = s.course.present? || group.size == size
          Series.new(label: "S#{n}", session: s, shots: group, total: round(group.sum { value(it) }), complete:)
        end
      end
    end
  end

  def complete_series = series.select(&:complete)
  def best_series = complete_series.size > 1 ? complete_series.max_by(&:total) : nil
  def worst_series = complete_series.size > 1 ? complete_series.min_by(&:total) : nil

  # Each card with the competition shots on it, in order; a card of sighters only is left out.
  def cards
    @cards ||= begin
      n = 0
      sessions.flat_map do |s|
        s.cards.filter_map do |card|
          on_card = card.shots.select { counts?(it) }.sort_by(&:fired_at)
          next if on_card.empty?

          n += 1
          label = single? || sessions.map { it.started_at.to_date }.uniq.one? ? "Card #{n}" : "#{s.started_at.strftime('%b %-d')} · Card #{n}"
          CardShots.new(label:, shots: on_card)
        end
      end
    end
  end

  # --- groups (shot in runs of 5 on one card: PracticeSession#group_of) ---------

  ShotGroup = Data.define(:label, :shots, :size_mm, :complete, :of)

  # Is any session of the set shot in groups? Then its pictures are about group
  # size, not score (SharePicture::Groups).
  def grouped? = sessions.any?(&:group_of)

  # Every group of the set's grouped sessions, in firing order, labelled G1, G2...
  def groups
    @groups ||= begin
      n = 0
      sessions.select(&:group_of).flat_map do |s|
        s.cards.sort_by(&:number).flat_map do |card|
          on_card = card.shots.select { counts?(it) }
          CardStats.new(on_card, spec).groups(of: s.group_of).map do |g|
            n += 1
            ShotGroup.new(label: "G#{n}", shots: g.shots, size_mm: g.size_mm, complete: g.complete, of: s.group_of)
          end
        end
      end
    end
  end

  def complete_groups = groups.select { it.complete && it.size_mm }
  def best_group = complete_groups.min_by(&:size_mm)
  def mean_group_mm = (complete_groups.any? ? (complete_groups.sum(&:size_mm) / complete_groups.size).round(1) : nil)

  def card_total(card) = round(card.shots.sum { value(it) })
  def card_inner_tens(card) = card.shots.count { inner_ten?(it) }

  # --- the numbers --------------------------------------------------------------

  def stats = @stats ||= CardStats.new(shots.reject(&:penalized?), spec, whole_rings: whole_rings?)

  # Mean of each card's group size, centre to centre (as the journal: a card change
  # mid-session doesn't make one huge group).
  def group_mm
    sizes = cards.filter_map { CardStats.new(it.shots, spec).group_size_mm }
    (sizes.sum / sizes.size).round(1) if sizes.any?
  end

  def shooting_seconds = sessions.sum(&:shooting_seconds)

  def seconds_per_shot
    gaps = cards.flat_map { CardStats.new(it.shots, spec).intervals_s }
    (gaps.sum / gaps.size.to_f).round if gaps.any?
  end

  # Where the shots landed, by ring: [ label, count ] from the 10 out, the last row
  # gathering everything from `low` down.
  def split
    low = spec.key == "pistol" ? 6 : 7
    rings = shots.map { it.final_ring.to_i }
    (low + 1..10).to_a.reverse.map { [ it.to_s, rings.count(it) ] } + [ [ "#{low} or less", rings.count { it <= low } ] ]
  end

  # The shots that missed, by which of eight 45-degree directions from the centre
  # they lie in (TargetSpec::DIRECTIONS order: right, high right, high, ...).
  def miss_ring = spec.key == "pistol" ? 8 : 9

  def misses_by_direction
    counts = Array.new(8, 0)
    shots.each do |s|
      next if s.final_ring.to_i > miss_ring

      angle = Math.atan2(s.final_y_mm, s.final_x_mm) * 180.0 / Math::PI % 360.0
      counts[(((angle + 22.5) % 360.0) / 45.0).floor % 8] += 1
    end
    counts
  end

  private
    def counts?(shot) = shot.scored? && !shot.sighter? && shot.final_x_mm && shot.final_y_mm

    def shots_of(session)
      session.cards.flat_map(&:shots).select { counts?(it) }.sort_by(&:fired_at)
    end

    def round(number, digits = 1) = whole_rings? && digits == 1 ? number.round : number.round(digits)
end
