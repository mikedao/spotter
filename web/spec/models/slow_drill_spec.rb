require "rails_helper"

RSpec.describe SlowDrill do
  let(:user) { create(:user) }
  let(:attrs) { { user:, shots: 30, string_size: 10, limit_seconds: 12, between_seconds: 10, string_rest_seconds: 60, shots_fired: 30, let_downs: 4, break_seconds: 210.0, performed_at: Time.current } }

  it "clamps the settings and falls back to the defaults" do
    expect(described_class.settings({})).to eq(shots: 10, string_size: 10, limit_seconds: 12, between_seconds: 10, string_rest_seconds: 60)
    expect(described_class.settings(shots: "999", limit_seconds: "1", string_size: "x")).to include(shots: 60, limit_seconds: 5, string_size: 10)
  end

  it "needs something done, no more shots than the drill has, and no impossible times" do
    expect(described_class.new(**attrs)).to be_valid
    expect(described_class.new(**attrs, shots_fired: 0, let_downs: 0)).not_to be_valid
    expect(described_class.new(**attrs, shots_fired: 31)).not_to be_valid
    expect(described_class.new(**attrs, break_seconds: 400)).not_to be_valid
  end

  it "works out its rates and summary" do
    drill = described_class.new(**attrs)
    expect(drill.first_time_rate).to eq(88)   # 30 of 34 raises became a shot
    expect(drill.mean_break_seconds).to eq(7.0)
    expect(drill.summary).to eq("30 of 30 slow shots in 12 s, 4 let down")
    expect(described_class.new(**attrs, shots_fired: 0, let_downs: 2, break_seconds: 0).mean_break_seconds).to be_nil
  end

  it "completes a plan block with its shots fired in its time or less" do
    drill = described_class.new(**attrs)
    expect(drill.completes?(30, 12)).to be true
    expect(drill.completes?(30, 8)).to be false      # settled in 12, the block wants 8
    expect(drill.completes?(40, 12)).to be false
    expect(described_class.new(**attrs, limit_seconds: 8).completes?(30, 12)).to be true
  end

  it "has slow blocks in the plan, all dry fire" do
    slow = TrainingPlan.weeks.flat_map(&:days).select { |day| day.blocks.any?(&:slow) }
    expect(slow).not_to be_empty
    expect(slow).to all(be_dry)   # the FWB 65 is never dry-fired
    pass = TrainingPlan.weeks.flat_map(&:days).flat_map(&:blocks).find { it.name == "Pass or let down" }
    expect(pass.slow.limit).to eq(8)
  end
end
