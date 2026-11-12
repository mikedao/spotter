require "rails_helper"

RSpec.describe Voice do
  it "offers exactly the engine's voices (engine/voicelines.py)" do
    out, status = Open3.capture2(EngineRunner.python, "-c", "import json, voicelines; print(json.dumps(voicelines.VOICES))",
                                 chdir: EngineRunner.engine_dir.to_s)
    skip "engine Python not available" unless status.success?
    engine = JSON.parse(out)
    expect(described_class::ALL.to_h { |id, v| [ id, [ v.name, v.accent, v.gender ] ] }).to eq engine
  end

  it "uses the user's voice, else the default" do
    expect(described_class.for(build(:user, voice: "bm_george")).name).to eq "George"
    expect(described_class.for(build(:user, voice: nil)).id).to eq "af_heart"
    expect(described_class.for(build(:user, voice: "gone"))).to eq described_class.find("af_heart")
  end

  it "refuses a sample for a voice that doesn't exist" do
    expect { described_class.sample_path("../../etc/passwd") }.to raise_error(ArgumentError)
  end
end
