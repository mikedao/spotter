# A day of the training plan as a post to CompetitiveShooter.org, made in the
# composer at /plan/W/D/share (it comes up when the day is ticked done; nothing is
# posted without Post). Up to the site's 4 pictures from available_kinds: the day's
# own card (PlanDayPicture), the plan's progress (PlanProgressPicture) and the
# sessions' pictures (the groups for group training); the caption says it in words.
#
#   share = PlanDayShare.new(user, 1, 2)
#   share.body      # => "Training plan, week 1 day 2: Hold and trigger (Pardini)\n..."
#   share.post!     # => SharedPost
class PlanDayShare
  class Invalid < StandardError; end

  # One block of the day and what was done in it: a headline value ("10/10") and
  # what it means; `done` when a timer or session finished the block's spec; `runs`
  # every timer run or session done for it, oldest first (empty: not done yet).
  Item = Data.define(:block, :name, :value, :detail, :done, :line, :runs) do
    def started? = runs.any?
  end

  # One session's numbers, for a shooting block: competition shots (sighters out),
  # scored as the session is, and its groups when the block shoots in runs.
  # Shot in groups, it is about group size: no score.
  SessionNumbers = Data.define(:session, :shots, :score, :average, :groups) do
    def text
      return "#{shots} shots · groups #{groups.join(' · ')} mm" if groups.any?

      [ ("#{score} over #{shots} shots" if shots.positive?), ("avg #{average}" if average) ].compact.join(" · ").presence || "no shots"
    end
  end

  # How the post looks, chosen in the composer (plan_day_shares/show): the colors,
  # the name and gear, and for the day's own card a headline of your own and
  # whether it shows the note and the plan's progress.
  Look = Data.define(:colors, :identity, :headline, :note, :progress) do
    def self.from(params, user)
      params = params.to_h.symbolize_keys
      new(colors: ShareColorway.key_for(params[:colors].presence || user.share_colors),
          identity: params[:identity] != "0",
          headline: params[:headline].to_s.squish.first(HEADLINE_MAX).presence,
          note: params[:show_note] != "0",
          progress: params[:show_progress] != "0")
    end

    def to_params = { colors:, identity: identity ? 1 : 0, headline: headline.to_s, show_note: note ? 1 : 0, show_progress: progress ? 1 : 0 }
  end
  HEADLINE_MAX = 60

  attr_reader :user, :enrollment, :day

  def initialize(user, week, day)
    @user = user
    @enrollment = user.plan_enrollment or raise Invalid, "Join the training plan first."
    @day = @enrollment.day(week.to_i, day.to_i) or raise ActiveRecord::RecordNotFound
    raise Invalid, "A rest day has nothing to post." if @day.rest?
  end

  def workout = enrollment.workout_for(day.week, day.day)
  def note = workout&.note
  def date = workout&.completed_at&.to_date || enrollment.scheduled_on(day.week, day.day)
  def date_text = date.strftime("%b %-d, %Y")
  def kind_text = day.dry? ? "Dry fire + air pistol" : "Air pistol"
  def heading = "Week #{day.week} · Day #{day.day}"

  def holds = @holds ||= user.hold_drills.where(plan_week: day.week, plan_day: day.day).order(:performed_at).to_a
  def slows = @slows ||= user.slow_drills.where(plan_week: day.week, plan_day: day.day).order(:performed_at).to_a
  def timeds = @timeds ||= user.timed_drills.where(plan_week: day.week, plan_day: day.day).order(:performed_at).to_a
  def sessions = @sessions ||= user.practice_sessions.for_plan_day(day.week, day.day).includes(cards: :shots).order(:started_at).to_a

  # Every block with something to measure (a timer or a session), in the day's
  # order, done or not. Warm-up, notes and the like have nothing to measure.
  def summary = @summary ||= day.blocks.filter_map { item_for(it) }

  # The blocks something was done in: what the post shows. The note goes in the caption.
  def items = summary.select(&:started?)

  def session_numbers(session)
    shots = session.cards.flat_map { |card| card.scored_shots.reject(&:sighter?) }
    stats = CardStats.new(shots, session.target_spec, whole_rings: session.whole_rings?)
    groups = session.group_of ? session.cards.flat_map { CardStats.new(it.scored_shots, session.target_spec).group_sizes(of: session.group_of) } : []
    SessionNumbers.new(session, stats.count, stats.score, stats.score_average, groups)
  end

  def done_count = enrollment.done_count
  def workout_count = enrollment.workout_count

  def body
    lines = [ "Training plan, week #{day.week} day #{day.day}: #{day.title}", day.focus, "" ]
    lines += items.map { "#{it.done ? '✓' : '·'} #{it.name}: #{it.line}" }
    lines += [ "", note ] if note.present?
    lines += [ "", "Plan: #{done_count} of #{workout_count} days done." ]
    lines.join("\n").strip.first(CompetitiveShooter::BODY_MAX)
  end

  # Dry fire is the Pardini (Bullseye), and those days finish on the air pistol too;
  # air days are the ISSF air pistol.
  def topics = day.dry? ? %w[ bullseye-precision-pistol international-issf-pistol ] : [ "international-issf-pistol" ]

  # The finished sessions shot for the day with scored shots, as one set, or nil.
  def session_set
    return @session_set if defined?(@session_set)

    finished = sessions.reject(&:live?).select { |s| s.cards.any? { it.scored_shots.any? } }
    @session_set = (ShareSet.new(finished) if finished.any? && finished.map(&:target).uniq.one?)
  rescue ShareSet::Invalid
    @session_set = nil
  end

  # "day" is the day's own picture; the rest are a session share's: the target and
  # the numbers, or for group training (5-shot groups on one card) the groups.
  def picture_kinds
    extra = if session_set.nil? then []
    elsif session_set.grouped? then %w[ groups ]
    else %w[ hero stats ]
    end
    [ "day", *extra ]
  end

  # Every picture the composer offers for this day, in order, with its label: the
  # day's own card, the plan's progress, and the sessions' pictures (the groups for
  # group training, else the target and score...).
  def available_kinds
    kinds = { "day" => "The day", "progress" => "Plan progress" }
    session_set ? kinds.merge(SharePicture.kinds_for(session_set).transform_keys(&:to_s)) : kinds
  end

  def default_look = Look.from({}, user)

  def picture(kind, colors: nil, look: nil)
    look ||= colors ? default_look.with(colors: ShareColorway.key_for(colors)) : default_look
    case kind
    when "day" then PlanDayPicture.new(self, look:)
    when "progress" then PlanProgressPicture.new(self, colors: look.colors, identity: look.identity)
    else SharePicture.build(kind, session_set, colors: look.colors, identity: look.identity)
    end
  end

  def posted = user.shared_posts.newest_first.where(plan_week: day.week, plan_day: day.day)

  # Posts the picked pictures (in the composer's order) with the caption and topics.
  def post!(kinds: picture_kinds, body: self.body, topics: self.topics, look: default_look)
    kinds = (available_kinds.keys & kinds).first(CompetitiveShooter::MAX_IMAGES)   # in the composer's order
    raise Invalid, "Pick at least one picture to post." if kinds.empty?

    images = kinds.map { |k| p = picture(k, look:); [ p.filename, p.jpeg ] }
    result = CompetitiveShooter.new(user.cso_api_key).post!(body:, topics:, images:)
    user.update!(share_colors: look.colors)
    user.shared_posts.create!(post_id: result["id"].to_s, url: result["url"].to_s, session_ids: session_set&.ids.to_a,
                              pictures: kinds, plan_week: day.week, plan_day: day.day)
  end

  private
    def item_for(block)
      if block.drill then hold_item(block)
      elsif block.slow then slow_item(block)
      elsif block.timed then timed_item(block)
      elsif block.session then session_item(block)
      end
    end

    # The run that finished the block, else the last one tried.
    def pick(runs) = runs.find { yield it } || runs.last

    def not_done(block, value) = Item.new(block, block.name, value, "not done", false, "not done", [])

    def hold_item(block)
      drill = pick(holds) { it.completes?(block.drill) } or return not_done(block, "0/#{block.drill.reps}")
      detail = "holds of #{drill.hold_seconds} s held · #{drill.held_seconds.round} s in all"
      detail += " · #{drill.let_downs} let down" if drill.let_downs.positive?
      Item.new(block, block.name, "#{drill.reps_done}/#{drill.reps}", detail, drill.completes?(block.drill), drill.summary, holds)
    end

    def slow_item(block)
      drill = pick(slows) { it.completes?(block.shots, block.slow.limit) } or return not_done(block, "0/#{block.shots}")
      bits = [ "shots broken inside #{drill.limit_seconds} s" ]
      bits << "#{drill.mean_break_seconds} s to break" if drill.mean_break_seconds
      bits << "#{drill.first_time_rate}% first time" if drill.first_time_rate
      Item.new(block, block.name, "#{drill.shots_fired}/#{drill.shots}", bits.join(" · "), drill.completes?(block.shots, block.slow.limit), drill.summary, slows)
    end

    def timed_item(block)
      drill = pick(timeds) { it.completes?(block.timed) } or return not_done(block, "0/#{block.timed.strings}")
      Item.new(block, block.name, "#{drill.strings_done}/#{drill.strings}", "strings of #{drill.shots} in #{drill.string_seconds} s",
               drill.completes?(block.timed), drill.summary, timeds)
    end

    # A shooting block: its sessions' shots and score together, the groups when it
    # shoots in runs.
    def session_item(block)
      shot = sessions.select { it.plan_block == block.number }
      return not_done(block, "0/#{block.shots}") if shot.empty?

      numbers = shot.map { session_numbers(it) }
      count = numbers.sum(&:shots)
      groups = numbers.flat_map(&:groups)
      done = shot.any?(&:completes_plan_block?)
      if groups.any?
        # Group training: the best group is the headline, then every group's size.
        best, mean = groups.min, (groups.sum / groups.size).round(1)
        of = shot.filter_map(&:group_of).first
        detail = "best of #{groups.size} groups of #{of} · avg #{mean} mm"
        line = "#{groups.size} groups of #{of}, best #{best} mm, avg #{mean} mm"
        return Item.new(block, block.name, "#{best} mm", detail, done, line, numbers)
      end

      score = numbers.sum(&:score)
      score = score.round(1) if score.is_a?(Float)
      Item.new(block, block.name, count.positive? ? score.to_s : "0", "#{count} shots", done, "#{score} over #{count} shots", numbers)
    end
end
