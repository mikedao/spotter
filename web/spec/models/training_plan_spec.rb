require "rails_helper"

RSpec.describe TrainingPlan do
  it "has 12 weeks of 7 days, in order, each in one phase" do
    expect(described_class.weeks.map(&:number)).to eq((1..12).to_a)
    expect(described_class.weeks.map { it.days.size }.uniq).to eq([ 7 ])
    expect(described_class.weeks.flat_map(&:days).map(&:kind).uniq).to all(be_in(TrainingPlan::KINDS))
  end

  it "gives every day a focus and blocks with real minutes" do
    described_class.weeks.flat_map(&:days).each do |day|
      expect(day.focus).to be_present, "#{day.ref} has no focus"
      expect(day.blocks).not_to be_empty
      expect(day.blocks.map(&:detail)).to all(be_present)
    end
  end

  it "fits workout days into about an hour: shorter in the taper, longer on match days" do
    described_class.workout_days.each do |day|
      range = if day.title.in?([ "Full match", "Test match" ]) then 100..115
      elsif day.phase.key == "test" then 35..65
      else 55..65
      end
      expect(day.minutes).to be_in(range), "#{day.ref} #{day.title} is #{day.minutes} min"
    end
  end

  it "tags air pistol days only, and keeps rest days short" do
    days = described_class.weeks.flat_map(&:days)
    expect(days.select(&:air?)).to all(satisfy { it.tags.any? })
    expect(days.reject(&:air?)).to all(satisfy { it.tags.empty? })
    expect(days.select(&:rest?).map(&:day).uniq).to eq([ 7 ])
  end

  it "scales shot counts by the week's volume, in fives" do
    full = described_class.day(2, 1).blocks.sum { it.shots.to_i }
    light = described_class.day(4, 1).blocks.sum { it.shots.to_i }
    expect(full).to be > light
    expect(described_class.weeks.flat_map(&:days).flat_map(&:blocks).filter_map(&:shots)).to all(satisfy { it % 5 == 0 && it >= 5 })
    expect(described_class.week(4)).to be_light
  end

  it "applies one-day overrides" do
    expect(described_class.day(12, 6).title).to eq("Test match")
    expect(described_class.day(11, 6).title).to eq("Full match")
  end

  it "never tells the shooter to dry-fire the air pistol" do
    texts = described_class.weeks.flat_map(&:days).select(&:dry?).flat_map { it.blocks.map(&:detail) }.join(" ")
    expect(texts).not_to match(/FWB/i)
  end

  it "parses a day reference and rejects nonsense" do
    expect(described_class.parse("3-2")).to eq([ 3, 2 ])
    expect(described_class.parse("13-1")).to be_nil
    expect(described_class.parse("3-8")).to be_nil
    expect(described_class.parse("x")).to be_nil
    expect(described_class.parse(nil)).to be_nil
  end
end
