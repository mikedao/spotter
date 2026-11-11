require "rails_helper"

RSpec.describe EngineRunner do
  let(:user) { create(:user, name: "Mike") }

  # A real short-lived process stands in for the engine, so liveness checks are
  # exercised for real without a camera.
  def finished_pid
    pid = Process.spawn("true")
    Process.wait(pid)
    pid
  end

  it "launches the engine for the user's new session with its id and one-time token" do
    allow(Process).to receive(:spawn).and_return(999_999)
    allow(described_class).to receive(:watch)

    session = described_class.start!(user:, target: "pistol", per_card: "10")

    expect(session).to have_attributes(user:, target: "pistol", per_card: 10, status: "starting", engine_pid: 999_999)
    expect(Process).to have_received(:spawn) do |env, *cmd, **opts|
      expect(env["SPOTTER_TOKEN"]).to eq session.run_token
      expect(cmd).to include("--auto", "--session-id", session.engine_session_id, "--per-card", "10", "--report-to")
      expect(cmd.each_cons(2)).to include([ "--stream-port", session.stream_port.to_s ])
      expect(opts[:chdir]).to end_with("engine")
    end
  end

  it "uses the camera the shooter picked, and remembers it" do
    allow(Process).to receive(:spawn).and_return(999_999)
    allow(described_class).to receive(:watch)

    session = described_class.start!(user:, target: "pistol", per_card: nil, camera: "http://192.168.1.40:8080/stream")

    expect(session.camera).to eq "http://192.168.1.40:8080/stream"
    expect(user.reload.last_camera).to eq "http://192.168.1.40:8080/stream"
    expect(Process).to have_received(:spawn) do |_env, *cmd, **|
      expect(cmd.each_cons(2)).to include([ "--device", "http://192.168.1.40:8080/stream" ])
    end
  end

  it "uses the microphone the shooter picked, as one argument, and remembers it" do
    allow(Process).to receive(:spawn).and_return(999_999)
    allow(described_class).to receive(:watch)

    session = described_class.start!(user:, target: "pistol", per_card: nil, camera: "1", mic: "Michael's iPhone Microphone")

    expect(session.mic).to eq "Michael's iPhone Microphone"
    expect(user.reload.last_mic).to eq "Michael's iPhone Microphone"
    expect(Process).to have_received(:spawn) do |_env, *cmd, **|
      expect(cmd).to include("--mic=Michael's iPhone Microphone")
    end
  end

  it "refuses a microphone name that could be read as an option" do
    [ "--help", "-x", "a\nb" ].each do |bad|
      expect { described_class.start!(user:, target: "pistol", per_card: nil, camera: "0", mic: bad) }
        .to raise_error(EngineRunner::BadCamera, /microphone/)
    end
  end

  it "refuses anything that isn't a camera number or a stream URL" do
    [ "0; rm -rf /", "--help", "file:///etc/passwd", "1 2" ].each do |bad|
      expect { described_class.start!(user:, target: "pistol", per_card: nil, camera: bad) }
        .to raise_error(EngineRunner::BadCamera)
    end
    expect(PracticeSession.count).to eq 0
  end

  it "runs one session at a time and says who is shooting" do
    running = create(:practice_session, user:, engine_pid: Process.pid, ended_at: nil)
    expect { described_class.start!(user: create(:user), target: "pistol", per_card: nil) }
      .to raise_error(EngineRunner::Busy, "Mike is shooting") { expect(it.session).to eq running }
  end

  it "ends a session whose engine died, keeping the end of its log" do
    log = Rails.root.join("tmp", "engine_spec.log")
    File.write(log, "camera 0: 1920x1080\nno input device matching 'Kiyo'. Inputs: ['MacBook']\n")
    session = create(:practice_session, user:, engine_pid: finished_pid, engine_log: log.to_s, ended_at: nil)

    described_class.reconcile!(session)

    expect(session).to have_attributes(status: "ended", ended_at: be_present)
    expect(session.engine_error).to include("no input device matching 'Kiyo'")
    expect(described_class.running).to be_nil
  end
end
