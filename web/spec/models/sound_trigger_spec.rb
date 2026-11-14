require "rails_helper"

# The browser judges sounds by the engine's own rule: the two must not drift.
RSpec.describe SoundTrigger do
  let(:engine) { EngineRunner.engine_dir.join("phase1.py").read }

  it "is the engine's TRIGGER_DB and TRIGGER_MS" do
    expect(engine[/^TRIGGER_DB = ([\d.]+)/, 1].to_f).to eq(described_class::DB)
    expect(engine[/^TRIGGER_MS = ([\d.]+)/, 1].to_f).to eq(described_class::MS)
  end

  it "needs both: loud enough and long enough" do
    expect(described_class.would_trigger?(68, 300)).to be true
    expect(described_class.would_trigger?(55, 300)).to be false
    expect(described_class.would_trigger?(68, 120)).to be false
  end
end
