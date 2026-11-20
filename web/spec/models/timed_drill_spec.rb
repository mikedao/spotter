require "rails_helper"

RSpec.describe TimedDrill do
  let(:user) { create(:user) }
  let(:attrs) { { user:, strings: 4, shots: 5, string_seconds: 20, rest_seconds: 30, strings_done: 4, performed_at: Time.current } }

  it "clamps the settings from a page's params and falls back to the defaults" do
    expect(described_class.settings({})).to eq(strings: 4, string_seconds: 20, shots: 5, rest_seconds: 30)
    expect(described_class.settings(strings: "99", string_seconds: "1", shots: "x", rest_seconds: "45"))
      .to eq(strings: 16, string_seconds: 5, shots: 5, rest_seconds: 45)
  end

  it "needs at least one string, and no more than the drill has" do
    expect(described_class.new(**attrs, strings_done: 0)).not_to be_valid
    expect(described_class.new(**attrs, strings_done: 5)).not_to be_valid
    expect(described_class.new(**attrs, strings_done: 2)).to be_valid
  end

  it "summarises itself" do
    expect(described_class.new(**attrs, strings_done: 3).summary).to eq("3 of 4 strings of 5 in 20 s")
  end

  describe "#completes?" do
    let(:spec) { TrainingPlan::TimedSpec.new(4, 20) }

    it "needs every string shot, in the block's time or less" do
      expect(described_class.new(**attrs).completes?(spec)).to be true
      expect(described_class.new(**attrs, string_seconds: 10).completes?(spec)).to be true    # faster is harder
      expect(described_class.new(**attrs, string_seconds: 30).completes?(spec)).to be false
      expect(described_class.new(**attrs, strings_done: 3).completes?(spec)).to be false
      expect(described_class.new(**attrs, strings: 3, strings_done: 3).completes?(spec)).to be false
    end
  end

  it "has timed blocks in the plan, with the strings and seconds the text says" do
    timed = TrainingPlan.weeks.flat_map(&:days).flat_map(&:blocks).select(&:timed)
    expect(timed).not_to be_empty
    expect(timed.map(&:timed).map(&:seconds).uniq).to contain_exactly(20, 10)
    expect(TrainingPlan.day(1, 2).blocks.find { it.name == "Timed sequence" }.timed).to eq(TrainingPlan::TimedSpec.new(4, 20))
    expect(TrainingPlan.weeks.flat_map(&:days).select { it.blocks.any?(&:timed) }).to all(be_dry)   # the FWB 65 is never dry-fired
  end
end
