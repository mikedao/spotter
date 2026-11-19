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

  Block = ::Data.define(:name, :minutes, :detail, :shots)
  Phase = ::Data.define(:key, :name, :summary, :weeks)
  Week = ::Data.define(:number, :phase, :focus, :volume, :days) do
    def light? = volume < 1
  end

  Day = ::Data.define(:week, :day, :phase, :title, :kind, :focus, :tags, :blocks, :light) do
    def air? = kind == "air"
    def dry? = kind == "dry"
    def rest? = kind == "rest"
    def minutes = blocks.sum(&:minutes)
    def shots = blocks.sum { it.shots.to_i }
    def ref = "#{week}-#{day}"
  end

  class << self
    def weeks = (@weeks ||= build)
    def week(number) = (weeks[number - 1] if number.between?(1, WEEKS))
    def day(week, day) = (self.week(week)&.days&.at(day - 1) if day.between?(1, DAYS_PER_WEEK))
    def name = data.fetch("name")
    def summary = data.fetch("summary")
    def total_days = WEEKS * DAYS_PER_WEEK

    # "3-2" -> [3, 2]; nil for anything that is not a day of the plan.
    def parse(ref)
      week, day = ref.to_s.split("-", 2).map { Integer(it, 10, exception: false) }
      [ week, day ] if week && day && self.day(week, day)
    end

    # Days that are a workout (not a rest or range day): what progress counts.
    def workout_days = weeks.flat_map(&:days).reject(&:rest?)

    def reload! = (@weeks = @data = nil)

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

      def build_day(week, day, phase, fields, volume)
        blocks = fields.fetch("blocks").map do |block|
          shots = scale(block["shots"], volume)
          Block.new(block.fetch("name"), block.fetch("minutes"), block.fetch("detail"), shots)
        end
        Day.new(week, day, phase, fields.fetch("title"), fields.fetch("kind"), fields.fetch("focus"),
                fields.fetch("tags", []), blocks, volume < 1)
      end

      # Shot counts follow the week's volume, in fives, never below five.
      def scale(shots, volume)
        return unless shots

        [ (shots * volume / 5.0).round * 5, 5 ].max
      end
  end
end
