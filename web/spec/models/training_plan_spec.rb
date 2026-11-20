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

  describe "block sessions" do
    let(:blocks) { described_class.weeks.flat_map(&:days).flat_map { |d| d.blocks.map { |b| [ d, b ] } } }

    it "gives every shooting block of an air pistol day a session of its own, and nothing else" do
      blocks.each do |day, block|
        expect(block.session.present?).to eq(day.air? && block.shots.present?), "#{day.ref} #{block.name}"
      end
    end

    it "preloads cards of 10 shots (groups measured by 5), and a match for the match blocks only" do
      sessions = blocks.filter_map { |_, b| b.session }
      expect(sessions.map(&:per_card).uniq).to contain_exactly(10)
      expect(sessions.map(&:group).uniq).to contain_exactly(nil, 5)
      expect(sessions.map(&:course).uniq).to contain_exactly(nil, "match")
      matches = blocks.select { |_, b| b.session&.course == "match" }
      expect(matches.map { |_, b| b.name }.uniq).to eq([ "Match" ])
      expect(matches.map { |d, _| d.ref }).to contain_exactly("8-6", "9-6", "10-6", "11-6", "12-6")
    end

    it "makes a day's tags its blocks' tags together" do
      expect(described_class.day(1, 1).tags).to eq([ "Groups", "Calling shots" ])
      expect(described_class.day(1, 2).tags).to be_empty
    end

    it "numbers blocks from 1 in their day and finds a shooting block by reference" do
      expect(described_class.day(1, 1).blocks.map(&:number)).to eq([ 1, 2, 3, 4 ])
      found = described_class.find_block("1-1-2")
      expect(found.block.name).to eq("Slow groups")
      expect(found.ref).to eq("1-1-2")
      expect(found.title).to eq("Week 1 · Day 1 · Slow groups")
    end

    it "finds nothing for a block with no session, or nonsense" do
      expect(described_class.find_block("1-1-1")).to be_nil   # the hold drill
      expect(described_class.find_block("1-1-9")).to be_nil
      expect(described_class.find_block("1-1")).to be_nil
      expect(described_class.find_block("x-y-z")).to be_nil
      expect(described_class.find_block(nil)).to be_nil
    end
  end
end
