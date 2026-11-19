require "rails_helper"

RSpec.describe HoldDrill do
  let(:user) { create(:user) }

  def drill(**attrs) = user.hold_drills.new({ reps: 10, hold_seconds: 8, rest_seconds: 20, reps_done: 8, let_downs: 2, held_seconds: 70, performed_at: Time.current }.merge(attrs))

  it "is valid with a finished drill, and says what happened" do
    expect(drill).to be_valid
    expect(drill.summary).to eq("8 of 10 holds of 8 s, 2 let down")
    expect(drill.completion).to eq(80)
    expect(drill).to be_finished
  end

  it "keeps a drill stopped early" do
    early = drill(reps_done: 3, let_downs: 0, held_seconds: 25)
    expect(early).to be_valid
    expect(early).not_to be_finished
    expect(early.summary).to eq("3 of 10 holds of 8 s")
  end

  it "refuses a drill with no holds, or more holds than it has" do
    expect(drill(reps_done: 0, let_downs: 0, held_seconds: 0)).not_to be_valid
    expect(drill(reps_done: 10, let_downs: 1)).not_to be_valid
  end

  it "refuses more seconds held than the drill allows" do
    expect(drill(held_seconds: 500)).not_to be_valid
  end

  it "keeps settings inside their limits" do
    expect(drill(reps: 0)).not_to be_valid
    expect(drill(hold_seconds: 2)).not_to be_valid
    expect(drill(rest_seconds: 500)).not_to be_valid
  end

  it "takes a plan day only as a whole day of the plan" do
    expect(drill(plan_week: 2, plan_day: 1)).to be_valid
    expect(drill(plan_week: 2)).not_to be_valid
    expect(drill(plan_week: 13, plan_day: 1)).not_to be_valid
    expect(drill(plan_week: 2, plan_day: 1).plan_ref).to eq("2-1")
  end

  describe ".settings" do
    it "defaults, and clamps what it is given" do
      expect(described_class.settings({})).to eq(reps: 10, hold_seconds: 8, rest_seconds: 20)
      expect(described_class.settings(reps: "500", hold_seconds: "1", rest_seconds: "x")).to eq(reps: 30, hold_seconds: 3, rest_seconds: 20)
      expect(described_class.settings(reps: "5", hold_seconds: "12", rest_seconds: "30")).to eq(reps: 5, hold_seconds: 12, rest_seconds: 30)
    end
  end
end

RSpec.describe HoldDrillStats do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  def make(day, **attrs)
    user.hold_drills.create!({ reps: 10, hold_seconds: 8, rest_seconds: 20, reps_done: 10, let_downs: 0, held_seconds: 80,
                               performed_at: Time.zone.local(2026, 11, day, 9) }.merge(attrs))
  end

  it "has nothing without drills" do
    expect(described_class.new(user)).not_to be_any
  end

  it "totals the holds, the time held and the steadiness, oldest first" do
    make(3, reps_done: 8, let_downs: 2, held_seconds: 70)
    make(1)
    stats = described_class.new(user)

    expect(stats.holds_done).to eq(18)
    expect(stats.held_seconds).to eq(150)
    expect(stats.steadiness).to eq(90)
    expect(stats.points.map(&:label)).to eq([ "Nov 1", "Nov 3" ])
    expect(stats.points.map(&:y)).to eq([ 100, 80 ])
  end

  it "reports the longest hold in a clean full run" do
    make(1)
    make(2, hold_seconds: 12, held_seconds: 120)
    make(3, hold_seconds: 20, reps_done: 9, let_downs: 1, held_seconds: 190)   # let one down: not clean
    expect(described_class.new(user).longest_hold).to eq(12)
  end

  it "formats the tiles" do
    make(1)
    tiles = described_class.new(user).tiles.to_h { [ it[0], it[1] ] }
    expect(tiles).to eq("Drills" => "1", "Time held" => "80 s", "Steadiness" => "100%", "Longest clean run" => "8 s")
  end

  it "applies the period" do
    travel_to(Time.zone.local(2026, 11, 20)) do
      user.hold_drills.create!(reps: 5, hold_seconds: 8, rest_seconds: 20, reps_done: 5, held_seconds: 40, performed_at: 60.days.ago)
      make(18)
      expect(described_class.new(user, days: "30").drills.size).to eq(1)
      expect(described_class.new(user).drills.size).to eq(2)
    end
  end
end
