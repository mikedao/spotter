require "rails_helper"

RSpec.describe RigCheck do
  let(:user) { create(:user) }

  def with_engine(script)
    ENV["SPOTTER_PYTHON"] = file_fixture(script).expand_path.to_s
    yield
  ensure
    ENV.delete("SPOTTER_PYTHON")
  end

  def wait_until_finished(klass)
    100.times { break if klass.state_for(user)&.finished; sleep 0.05 }
    klass.state_for(user)
  end

  after { FileUtils.rm_rf(RigCheck::Locate.dir) }

  describe RigCheck::CameraVerdict do
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

    it "only warns about a bow up to 0.5 mm (a used card's holes read as bow)" do
      check = described_class.new(good.merge("flat_worst_mm" => -0.43), Time.current)
      expect(check).to be_ok
      expect(check.verdicts.find { it.label == "Card flat" }.text).to include("Slightly bowed", "fresh card")
    end

    it "reports a target it can't find" do
      check = described_class.new({ "found" => false, "reason" => "no sufficiently large, round dark region found" }, Time.current)
      expect(check).not_to be_ok
      expect(check.verdicts.first.text).to include("Not found")
    end
  end

  describe RigCheck::Locate do
    it "streams each live result and keeps the latest" do
      with_engine("fake_locate.sh") do
        described_class.start!(user:, camera: "1", target: "pistol")
        state = wait_until_finished(described_class)

        expect(state).to have_attributes(finished: true, error: nil)
        latest = described_class.latest(user)
        expect(latest).to be_ok
        expect([ latest.seq, latest.sharpness, latest.camera ]).to eq [ 2, 772.0, "1" ]
      end
    end

    it "says how a check that died ended, and its last error, instead of just 'it stopped'" do
      with_engine("fake_locate_crash.sh") do
        described_class.start!(user:, camera: "1", target: "pistol")
        state = wait_until_finished(described_class)
        expect(state.error).to eq "it crashed (SIGSEGV): cv2.error: stream read failed"
      end
    end

    it "waits while a session is using the camera" do
      create(:practice_session, engine_pid: Process.pid, ended_at: nil)
      expect { described_class.start!(user:, camera: "0", target: "pistol") }.to raise_error(RigCheck::Busy, /is shooting/)
    end

    it "refuses a bad camera before running anything" do
      expect { described_class.start!(user:, camera: "--help", target: "pistol") }.to raise_error(EngineRunner::BadCamera)
      expect(described_class.state_for(user)).to be_nil
    end
  end

  describe RigCheck::Listen do
    it "streams the level meter and each sound, then a summary" do
      with_engine("fake_listen.sh") do
        described_class.start!(user:, mic: "Razer Kiyo", seconds: 5)
        state = wait_until_finished(described_class)

        expect(state).to have_attributes(finished: true, error: nil)
        expect(state.data["level"]).to include("over_db" => 9.0, "floor_dbfs" => -61.0)
        expect(state.data["sounds"].map { it["would_trigger"] }).to eq [ false, true ]
        expect(state.data["summary"]["floor_dbfs"]).to eq(-61.0)
        expect(RigCheck.running_check).to be_nil
      end
    end

    it "needs a real microphone" do
      expect { described_class.start!(user:, mic: "none", seconds: 5) }.to raise_error(EngineRunner::BadCamera)
      expect { described_class.start!(user:, mic: "--help", seconds: 5) }.to raise_error(EngineRunner::BadCamera)
    end

    it "is private to the user who ran it" do
      with_engine("fake_listen.sh") do
        described_class.start!(user:, mic: "Razer Kiyo", seconds: 5)
        expect(described_class.state_for(create(:user))).to be_nil
        wait_until_finished(described_class)
      end
    end
  end
end
