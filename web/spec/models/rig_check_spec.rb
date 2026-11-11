require "rails_helper"

RSpec.describe RigCheck do
  let(:user) { create(:user) }

  describe RigCheck::Locate do
    let(:good) do
      { "found" => true, "camera" => "1", "view_deg" => 26.0, "edge_rms_px" => 0.43, "perspective" => true,
        "ring_rms_mm" => 0.11, "rings" => 10, "flat_worst_mm" => -0.08, "flat_worst_at" => [ 7, 225 ],
        "mm_per_px" => 0.197, "ring1_offscreen" => [], "brightness" => 66.8, "saturated_pct" => 0.0 }
    end

    it "says a good rig is ready to shoot" do
      check = described_class.new(good, Time.current)
      expect(check).to be_ok
      expect(check.verdicts.map(&:level)).to all(be_in(%i[ good info ]))
    end

    it "says what to fix" do
      bad = good.merge("edge_rms_px" => 1.6, "perspective" => false, "perspective_reason" => "only 12 ring points found",
                       "ring1_offscreen" => [ "top" ], "saturated_pct" => 3.2)
      texts = described_class.new(bad, Time.current).verdicts.map(&:text).join(" ")
      expect(texts).to include("Blurry", "couldn't be fitted", "Ring 1 runs off the top", "blown out")
    end

    it "reports a target it can't find" do
      check = described_class.new({ "found" => false, "reason" => "no sufficiently large, round dark region found" }, Time.current)
      expect(check).not_to be_ok
      expect(check.verdicts.first.text).to include("Not found")
    end

    it "runs the engine's locate --json on the chosen camera" do
      allow(Open3).to receive(:capture3).and_return([ "#{good.except('camera').to_json}\n", "", instance_double(Process::Status, success?: true) ])
      check = described_class.run!(user:, camera: "1", target: "pistol")
      expect(Open3).to have_received(:capture3).with(EngineRunner.python, "phase1.py", "locate", "--json", "--target", "pistol",
                                                     "--device", "1", "--frames", "4", "--overlay", anything, chdir: anything)
      expect(check.camera).to eq "1"
      expect(described_class.latest(user).found?).to be true
    end

    it "waits while a session is using the camera" do
      create(:practice_session, engine_pid: Process.pid, ended_at: nil)
      expect { described_class.run!(user:, camera: "0", target: "pistol") }.to raise_error(RigCheck::Busy, /is shooting/)
    end
  end

  describe RigCheck::Listen do
    around do |example|
      ENV["SPOTTER_PYTHON"] = file_fixture("fake_listen.sh").expand_path.to_s
      example.run
    ensure
      ENV.delete("SPOTTER_PYTHON")
    end

    it "streams each sound, marked with whether it would trigger, then a summary" do
      described_class.start!(user:, mic: "Razer Kiyo", seconds: 5)
      50.times { break if described_class.state_for(user).finished; sleep 0.05 }

      state = described_class.state_for(user)
      expect(state).to have_attributes(finished: true, error: nil, trigger_db: 45.0)
      expect(state.sounds.map { it["would_trigger"] }).to eq [ false, true ]
      expect(state.shots).to eq 1
      expect(state.summary["floor_dbfs"]).to eq(-61.0)
      expect(described_class).not_to be_running
    end

    it "needs a real microphone" do
      expect { described_class.start!(user:, mic: "none", seconds: 5) }.to raise_error(EngineRunner::BadCamera)
      expect { described_class.start!(user:, mic: "--help", seconds: 5) }.to raise_error(EngineRunner::BadCamera)
    end

    it "is private to the user who ran it" do
      described_class.start!(user:, mic: "Razer Kiyo", seconds: 5)
      expect(described_class.state_for(create(:user))).to be_nil
    end
  end
end
