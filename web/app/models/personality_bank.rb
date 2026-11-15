# A personality's lines: a large bank it picks from, by situation
# (engine/voice/personalities/<id>_seed.txt and <id>_bank/*.txt, one line each:
# "situation | line"). Situations are the shot's step (inner, ten, s95, s90,
# eight, seven, awful), the moments (tens_streak, nine_run, drop_after_run,
# flyer, tip <direction>), card / series / match / session lines, penalties,
# diagnostic flags and the engine's own lines ("ready", "card off" ...).
# Placeholders: {n} {total} {shots} {avg} {best}; a line is only picked when
# every placeholder in it has a value.
#
# Never the same line twice in a session until a situation's lines run out
# (kept in this process: the app is one Puma process).
#
#   bank = PersonalityBank.new("katey", session)
#   bank.pick("ten")                          # => "you're officially allowed at my table. on probation."
#   bank.pick("card_done", total: "87")       # => "card's done. 87. ..."
class PersonalityBank
  @used = Hash.new { |h, k| h[k] = Set.new }
  @lock = Mutex.new
  class << self
    attr_reader :used, :lock

    def dir = EngineRunner.engine_dir.join("voice", "personalities")
    def files(id) = [ dir.join("#{id}_seed.txt"), *dir.join("#{id}_bank").glob("*.txt").sort ].select(&:exist?)
    def available?(id) = files(id).any?

    # { situation => [ line, ... ] }, read once per process.
    def lines(id)
      (@lines ||= {})[id.to_s] ||= files(id).flat_map { it.read.lines }.filter_map do |line|
        next if line.start_with?("#") || !line.include?(" | ")

        line.chomp.split(" | ", 2).map(&:strip)
      end.group_by(&:first).transform_values { |pairs| pairs.map(&:last).uniq }
    end

    def reset! = (@lines = nil; lock.synchronize { used.clear })
  end

  def initialize(id, session, random: Random.new)
    @id, @session, @random = id.to_s, session, random
  end

  def has?(situation) = self.class.lines(@id).key?(situation)

  # A line for the first situation (of several, in order) that has one, with the
  # placeholders filled; nil when none does.
  def pick(*situations, **values)
    values = values.transform_keys(&:to_s).compact
    situations.flatten.each do |situation|
      options = Array(self.class.lines(@id)[situation]).select { |l| l.scan(/\{(\w+)\}/).flatten.all? { values.key?(it) } }
      next if options.empty?

      line = choose(situation, options)
      return values.reduce(line) { |text, (k, v)| text.gsub("{#{k}}", v.to_s) }
    end
    nil
  end

  # Pick among several pools at once (e.g. the card-total lines that fit), weighted by size.
  def pick_any(situations, **values)
    pool = situations.select { has?(it) }
    return nil if pool.empty?

    weights = pool.map { self.class.lines(@id)[it].size }
    r = @random.rand(weights.sum)
    chosen = pool.zip(weights).find { |_, w| (r -= w) < 0 }.first
    pick(chosen, *(pool - [ chosen ]), **values)
  end

  private
    def choose(situation, options)
      key = [ @session.id, @id, situation ]
      self.class.lock.synchronize do
        used = self.class.used[key]
        fresh = options.reject { used.include?(it) }
        if fresh.empty?
          used.clear
          fresh = options
        end
        fresh.sample(random: @random).tap { used << it }
      end
    end
end
