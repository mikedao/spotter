require "rails_helper"

RSpec.describe "Rig setup" do
  let(:user) { create(:user) }

  before { sign_in(user) }
  after { FileUtils.rm_rf(RigCheck::Locate.dir) }

  it "offers the camera and sound checks" do
    get setup_path
    expect(response.body).to include("Camera check", "Sound check", "Check the camera", "Listen")
  end

  it "runs the camera check and shows its verdicts" do
    data = { "found" => true, "view_deg" => 20.0, "edge_rms_px" => 0.4, "perspective" => true, "ring_rms_mm" => 0.1,
             "rings" => 10, "flat_worst_mm" => 0.05, "flat_worst_at" => [ 3, 15 ], "mm_per_px" => 0.2,
             "ring1_offscreen" => [], "brightness" => 70, "saturated_pct" => 0 }
    allow(Open3).to receive(:capture3).and_return([ data.to_json, "", instance_double(Process::Status, success?: true) ])

    post locate_setup_path, params: { camera: "0", target: "pistol" }
    follow_redirect!
    expect(response.body).to include("Ready to shoot", "Sharp")
    expect(user.reload.last_camera).to eq "0"
  end

  it "has no overlay to show before a check" do
    get locate_overlay_setup_path
    expect(response).to have_http_status(:not_found)
  end
end
