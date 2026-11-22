# The 12-week cross-training plan (config/training_plan.yml): what to do on each
# day of each week. Plain data, like Course - nothing here is stored per user.
# PlanEnrollment says which day a user is on; PlanWorkout what they finished.
#
#   TrainingPlan.day(3, 2)        # => week 3, day 2
#   TrainingPlan.week(3).focus
#   TrainingPlan.weeks.size       # => 12
class TrainingPlan
  WEEKS = 12
  DAYS_PER_WEEK = 7
  KINDS = %w[ air dry rest ].freeze

  # session: a SessionSpec on an air pistol shooting block (its own Spotter session, preloaded);
  # drill: a HoldSpec on a hold-drill block (the guided hold timer). number: 1-based in its day.
  Block = ::Data.define(:number, :name, :minutes, :detail, :shots, :drill, :timed, :slow, :session)
  HoldSpec = ::Data.define(:reps, :hold)
  SlowSpec = ::Data.define(:limit)   # slow: each shot broken within `limit` seconds (the slow dry fire timer; shots from the block)
  TimedSpec = ::Data.define(:strings, :seconds)   # timed: strings of 5 in `seconds` (the timed-fire timer)
  SessionSpec = ::Data.define(:per_card, :group, :course, :tags)
  # A shooting block found by its reference: the day it is in and the block.
  Found = ::Data.define(:day, :block) do
    def ref = "#{day.ref}-#{block.number}"
    def title = "Week #{day.week} · Day #{day.day} · #{block.name}"
  end
  Phase = ::Data.define(:key, :name, :summary, :weeks)
  Week = ::Data.define(:number, :phase, :focus, :volume, :days) do
    def light? = volume < 1
  end

  # variant: nil as written, "match" for a range day a shooter made a match (PlanEnrollment#match_days).
  Day = ::Data.define(:week, :day, :phase, :title, :kind, :focus, :blocks, :light, :range, :variant) do
    def match? = variant == "match"
    def air? = kind == "air"
    def dry? = kind == "dry"
    def rest? = kind == "rest"
    def range? = range
    def minutes = blocks.sum(&:minutes)
    def tags = blocks.flat_map { it.session&.tags.to_a }.uniq
    def session_blocks = blocks.select(&:session)
    def block(number) = blocks.find { it.number == number }
    def shots = blocks.sum { it.shots.to_i }
    def ref = "#{week}-#{day}"
  end

  class << self
    def weeks = (@weeks ||= build)
    def week(number) = (weeks[number - 1] if number.between?(1, WEEKS))
    # match: the range day as a match instead (only a range day has one).
    def day(week, day, match: false)
      found = (self.week(week)&.days&.at(day - 1) if day.between?(1, DAYS_PER_WEEK))
      match && found&.range? ? match_day(found) : found
    end

    # A range day turned into a full match: the yml's `match_day`, on that day's slot.
    # It stays the week's range day (one per week), so it swaps like one.
    def match_day(range_day)
      (@match_days ||= {})[range_day.ref] ||= begin
        fields = data.fetch("match_day")
        week = self.week(range_day.week)
        build_day(range_day.week, range_day.day, range_day.phase, fields.merge("range" => true), week.volume, variant: "match")
      end
    end
    def name = data.fetch("name")
    def summary = data.fetch("summary")
    def total_days = WEEKS * DAYS_PER_WEEK

    # "3-2" -> [3, 2]; nil for anything that is not a day of the plan.
    def parse(ref)
      week, day = ref.to_s.split("-", 2).map { Integer(it, 10, exception: false) }
      [ week, day ] if week && day && self.day(week, day)
    end

    # "3-1-2" -> the shooting block (it has a session of its own) with that reference, else nil.
    # With an enrollment, a range day it made a match resolves to the match.
    def find_block(ref, enrollment: nil)
      week, day, number = ref.to_s.split("-", 3).map { Integer(it, 10, exception: false) }
      return unless week && day && number

      plan_day = enrollment ? enrollment.day(week, day) : self.day(week, day)
      block = plan_day&.block(number)
      Found.new(plan_day, block) if block&.session
    end

    # Days that are a workout (every plan day now; a rest kind is left for safety): what progress counts.
    def workout_days = weeks.flat_map(&:days).reject(&:rest?)

    def reload! = (@weeks = @data = @match_days = nil)

    private
      def data = (@data ||= YAML.safe_load_file(Rails.root.join("config/training_plan.yml")))

      def build
        overrides = data.fetch("overrides", {})
        data.fetch("phases").flat_map do |phase_data|
          first, last = phase_data.fetch("weeks")
          phase = Phase.new(phase_data.fetch("key"), phase_data.fetch("name"), phase_data.fetch("summary"), first..last)
          (first..last).map do |number|
            info = data.fetch("weeks").fetch(number)
            volume = info.fetch("volume").to_f
            days = phase_data.fetch("days").each_with_index.map do |template, i|
              day = i + 1
              build_day(number, day, phase, template.merge(overrides.fetch("#{number}-#{day}", {})), volume)
            end
            Week.new(number, phase, info.fetch("focus"), volume, days)
          end
        end.sort_by(&:number)
      end

      def build_day(week, day, phase, fields, volume, variant: nil)
        blocks = fields.fetch("blocks").each_with_index.map do |block, i|
          series = block.fetch("series", 5)
          fixed = block["fixed"] == true || block.dig("session", "course").present?
          # Live fire comes in whole cards of ten (no half-used cards); dry fire by its series.
          shots = fixed ? block["shots"] : scale(block["shots"], volume, block["session"] ? 10 : series)
          drill = block["drill"]&.then { HoldSpec.new(it.fetch("reps"), it.fetch("hold")) }
          slow = block["slow"]&.then { SlowSpec.new(it.fetch("limit")) }
          timed = block["timed"]&.then { TimedSpec.new(it.fetch("strings"), it.fetch("seconds")) }
          session = block["session"]&.then { SessionSpec.new(it.fetch("per_card"), it["group"], it["course"], it.fetch("tags", [])) }
          Block.new(i + 1, block.fetch("name"), block.fetch("minutes"), fill(block.fetch("detail"), shots, series), shots, drill, timed, slow, session)
        end
        Day.new(week, day, phase, fields.fetch("title"), fields.fetch("kind"), fields.fetch("focus"), blocks, volume < 1, fields["range"] == true, variant)
      end

      # Shot counts follow the week's volume in whole series (of 5 or 10), never below one series.
      def scale(shots, volume, series)
        return unless shots

        [ (shots * volume / series.to_f).round * series, series ].max
      end

      NUMBER_WORDS = %w[ zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen
                         sixteen seventeen eighteen nineteen twenty ].freeze

      def word(n) = NUMBER_WORDS[n] || n.to_s

      # The detail's counts, as asked that week: {shots} {shots_word} {Shots_word} {series} {Series}.
      def fill(detail, shots, series)
        return detail unless shots

        count = shots / series
        detail.gsub("{shots}", shots.to_s).gsub("{shots_word}", word(shots)).gsub("{Shots_word}", word(shots).capitalize)
              .gsub("{series}", word(count)).gsub("{Series}", word(count).capitalize)
      end
  end
end
