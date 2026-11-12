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
    expect(response.body).to include("10m Air Pistol", "camera 1", "check not passed", "no shot heard")

    allow(EngineRunner).to receive(:start!).and_return(create(:practice_session, user:))
    post practice_sessions_path, params: { practice_session: { target: "pistol", per_card: 10, camera: "1", mic: "Razer Kiyo" } }
    expect(EngineRunner).to have_received(:start!).with(user:, target: "pistol", per_card: "10", camera: "1", mic: "Razer Kiyo")
  end

  it "sends you to the range screen if your session is already running" do
    running = create(:practice_session, user:, status: "ready", engine_pid: Process.pid)
    allow(EngineRunner).to receive(:running).and_return(running)
    get setup_camera_path
    expect(response).to redirect_to(practice_session_path(running))
  end
end
