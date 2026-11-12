# The courses of fire the engine's virtual range officer runs (engine/course.py,
# which holds the timings and commands; spec/models/course_spec.rb checks the
# two agree). A session with no course is practice: no clock, every shot counts.
#
#   Course.find("match").shots      # => 60
#   Course.for(session)              # => nil for practice
class Course
  Data = ::Data.define(:key, :name, :description, :shots, :series_size, :whole_rings_for) do
    # ISSF: pistol qualification is scored in whole rings, finals and rifle in decimals.
    def whole_rings?(target) = whole_rings_for.include?(target)
  end

  ALL = {
    "match" => Data.new("match", "Match", "60 shots in 75 minutes, after 15 minutes of sighting", 60, 10, %w[ pistol ]),
    "final" => Data.new("final", "Final", "24 shots: 2 series of 5 in 250 s, then 14 single shots in 50 s", 24, nil, []),
    "ranking" => Data.new("ranking", "Final (ranking + medal match)",
                          "25 shots in 5-shot series of 250 s, then 8 medal match shots in 50 s", 33, nil, [])
  }.freeze

  def self.find(key) = ALL.fetch(key.to_s)
  def self.valid?(key) = ALL.key?(key.to_s)
  def self.for(session) = session.course.present? ? find(session.course) : nil
end
