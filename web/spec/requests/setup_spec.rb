require "rails_helper"

RSpec.describe "Rig setup" do
  let(:user) { create(:user) }

  before { sign_in(user) }
  after { FileUtils.rm_rf(RigCheck::Locate.dir) }

  it "offers the camera and sound checks" do
    get setup_path
    expect(response.body).to include("Camera check", "Sound check", "Start live check", "Listen")
  end

  it "starts the live camera check and shows its latest verdicts" do
    ENV["SPOTTER_PYTHON"] = file_fixture("fake_locate.sh").expand_path.to_s
    post locate_setup_path, params: { camera: "1", target: "pistol" }
    100.times { break if RigCheck::Locate.state_for(user)&.finished; sleep 0.05 }

    follow_redirect!
    expect(response.body).to include("Ready to shoot", "Sharpness")
    expect(user.reload.last_camera).to eq "1"
  ensure
    ENV.delete("SPOTTER_PYTHON")
  end

  it "has no overlay to show before a check" do
    get locate_overlay_setup_path
    expect(response).to have_http_status(:not_found)
  end
end
