require "rails_helper"

# The new-session setup wizard: camera > camera check > microphone > start.
RSpec.describe "New session setup" do
  let(:user) { create(:user, name: "Mike") }

  before do
    sign_in(user)
    FileUtils.mkdir_p(CameraProbe.dir)
    CameraProbe.results_path.write({ cameras: [ { index: 0, name_hint: "MacBook Neo Camera" }, { index: 1, name_hint: "Razer Kiyo" } ],
                                     microphones: [ { name: "MacBook Neo Microphone" }, { name: "Razer Kiyo" } ] }.to_json)
  end

  after do
    FileUtils.rm_rf(CameraProbe.dir)
    FileUtils.rm_rf(RigCheck::Locate.dir)
  end

  def with_engine(script)
    ENV["SPOTTER_PYTHON"] = file_fixture(script).expand_path.to_s
    yield
  ensure
    ENV.delete("SPOTTER_PYTHON")
  end

  def wait_until_finished(klass)
    100.times { break if klass.state_for(user)&.finished; sleep 0.05 }
  end

  it "starts from Practice by looking for cameras" do
    get practice_sessions_path
    expect(response.body).to include("New session")

    allow(CameraProbe).to receive(:run!)
    post setup_path
    expect(CameraProbe).to have_received(:run!)
    expect(response).to redirect_to(setup_camera_path)
  end

  it "lists only the cameras the last search found" do
    user.update!(last_camera: "3")   # gone since
    get setup_camera_path
    expect(response.body).to include("MacBook Neo Camera", "Razer Kiyo", "1. Camera")
    expect(response.body).not_to include("camera 3")
  end

  it "asks for a device search before there is anything to pick" do
    FileUtils.rm_rf(CameraProbe.dir)
    get setup_camera_path
    expect(response.body).to include("No cameras looked for yet")
  end

  it "checks the chosen camera live and unlocks Next at Ready to shoot" do
    with_engine("fake_locate.sh") do
      post setup_camera_path, params: { camera: "1", target: "pistol" }
      expect(response).to redirect_to(setup_check_path)
      wait_until_finished(RigCheck::Locate)
    end
    expect(user.reload).to have_attributes(last_camera: "1", last_mic: "Razer Kiyo")   # the camera's own mic

    get setup_check_path
    expect(response.body).to include("Ready to shoot", "Sharpness", %(href="#{setup_microphone_path}"))
    expect(response.body).not_to include("Continue anyway")
  end

  it "keeps Next locked until the camera check passes, with a way past it" do
    user.update!(last_camera: "1")
    get setup_check_path
    expect(response.body).to include("Unlocks at", "Continue anyway", "Check again")
  end

  it "refuses something that isn't a camera" do
    post setup_camera_path, params: { camera: "url", camera_url: "--help", target: "pistol" }
    expect(response).to redirect_to(setup_camera_path)
    expect(flash[:alert]).to include("isn't a camera")
  end

  it "listens on the chosen microphone and unlocks Next once a shot would trigger" do
    user.update!(last_camera: "1")
    with_engine("fake_listen.sh") do
      post setup_microphone_path, params: { mic: "Razer Kiyo" }
      wait_until_finished(RigCheck::Listen)
    end
    expect(user.reload.last_mic).to eq "Razer Kiyo"

    get setup_microphone_path
    expect(response.body).to include("would trigger", %(href="#{setup_start_path}"))
  end

  it "remembers a sound check that heard a shot, and skips it next time for that microphone" do
    user.update!(last_camera: "1")
    with_engine("fake_listen.sh") do
      post setup_microphone_path, params: { mic: "Razer Kiyo" }
      wait_until_finished(RigCheck::Listen)
    end
    get setup_microphone_path
    expect(user.reload.sound_check).to include("mic" => "Razer Kiyo")

    RigCheck.reset!   # a new session: no check running or remembered in memory
    get setup_microphone_path
    expect(response).to redirect_to(setup_start_path)
    follow_redirect!
    expect(response.body).to include("✓ heard a shot", "sound check", "check again or change")

    get setup_microphone_path(again: 1)   # asked to: the check, as before
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Does the microphone hear your shots?")
  end

  it "asks again when the remembered check passed at a different trigger level" do
    # 2026-11-13: a check passed at +45 dB kept being trusted after the trigger rose
    # to +62, and a whole session's shots went unheard
    user.update!(last_camera: "1", last_mic: "Razer Kiyo",
                 sound_check: { "mic" => "Razer Kiyo", "at" => 1.day.ago.iso8601, "trigger_db" => 45.0, "trigger_ms" => 180.0 })
    get setup_microphone_path
    expect(response).to have_http_status(:ok)

    user.update!(sound_check: user.sound_check.merge("trigger_db" => SoundTrigger::DB))
    get setup_microphone_path
    expect(response).to redirect_to(setup_start_path)
  end

  describe "this browser's microphone" do
    before { user.update!(last_camera: "1") }

    it "is offered first, and runs the sound check in the page" do
      get setup_microphone_path
      expect(response.body).to include("This device&#39;s microphone")

      post setup_microphone_path, params: { mic: CameraProbe::BROWSER_MIC }
      expect(response).to redirect_to(setup_microphone_path(again: 1))
      expect(user.reload.last_mic).to eq("browser")
      follow_redirect!
      expect(response.body).to include('data-controller="browser-listen"', setup_heard_path)
      expect(response.body).not_to include('id="listen_meter"')   # not the engine's check
    end

    it "remembers a shot the page heard - at the engine's rule, not below it" do
      post setup_heard_path, params: { over_db: 58.0, len_ms: 300 }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.sound_check).to be_nil

      post setup_heard_path, params: { over_db: 69.4, len_ms: 310 }, as: :json
      expect(response).to have_http_status(:no_content)
      expect(user.reload.sound_check).to include("mic" => "browser", "loudest_db" => 69.4, "trigger_db" => SoundTrigger::DB)

      get setup_microphone_path   # passed before, and a browser is always "connected"
      expect(response).to redirect_to(setup_start_path)
      follow_redirect!
      expect(response.body).to include("This device&#39;s microphone", "✓ heard a shot")
    end
  end

  it "asks again for a different microphone, or one that isn't connected" do
    user.update!(last_camera: "1", last_mic: "MacBook Neo Microphone",
                 sound_check: { "mic" => "Razer Kiyo", "at" => 1.day.ago.iso8601, "trigger_db" => SoundTrigger::DB, "trigger_ms" => SoundTrigger::MS })
    get setup_microphone_path
    expect(response).to have_http_status(:ok)

    user.update!(last_mic: "Old USB Mic", sound_check: { "mic" => "Old USB Mic", "at" => 1.day.ago.iso8601, "trigger_db" => SoundTrigger::DB, "trigger_ms" => SoundTrigger::MS })
    get setup_microphone_path   # not in the last device search
    expect(response).to have_http_status(:ok)
  end

  it "goes camera only without a sound check" do
    user.update!(last_camera: "1")
    post setup_microphone_path, params: { mic: CameraProbe::NO_MIC }
    expect(response).to redirect_to(setup_start_path)
    follow_redirect!
    expect(response.body).to include("None - camera only", "Start session")
  end

  it "says on Start what wasn't checked, and starts the session with the choices" do
    user.update!(last_camera: "1", last_mic: "Razer Kiyo")
    get setup_start_path
    expect(response.body).to include("10m Air Pistol", "camera 1", "check not passed", "no shot heard",
                                     "Practice", "Match", "Final (ranking + medal match)")

    allow(EngineRunner).to receive(:start!).and_return(create(:practice_session, user:))
    post practice_sessions_path, params: { practice_session: { target: "pistol", per_card: 10, camera: "1", mic: "Razer Kiyo" } }
    expect(EngineRunner).to have_received(:start!).with(user:, target: "pistol", per_card: "10", camera: "1", mic: "Razer Kiyo",
                                                         course: nil, gear: { gun: nil, pellet: nil, gun_adjustments: nil })
  end

  it "starts a match with the range officer" do
    user.update!(last_camera: "1", last_mic: "Razer Kiyo")
    allow(EngineRunner).to receive(:start!).and_return(create(:practice_session, user:))
    post practice_sessions_path, params: { practice_session: { target: "pistol", per_card: 10, camera: "1", mic: "Razer Kiyo", course: "match" } }
    expect(EngineRunner).to have_received(:start!).with(hash_including(course: "match"))
  end

  it "sends you to the range screen if your session is already running" do
    running = create(:practice_session, user:, status: "ready", engine_pid: Process.pid)
    allow(EngineRunner).to receive(:running).and_return(running)
    get setup_camera_path
    expect(response).to redirect_to(practice_session_path(running))
  end
end
