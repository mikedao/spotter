require "rails_helper"

RSpec.describe DeviceChoice do
  let(:probe) do
    CameraProbe.new({ "cameras" => [
      { "index" => 0, "name_hint" => "MacBook Neo Camera" },
      { "index" => 1, "name_hint" => "Michael's iPhone Camera" }
    ], "microphones" => [ { "name" => "MacBook Neo Microphone" }, { "name" => "Michael's iPhone Microphone" } ] }, Time.current)
  end

  def choice(probe: self.probe, **user) = described_class.new(user: build(:user, **user), probe:)

  it "never offers a remembered camera or microphone that isn't there now" do
    c = choice(last_camera: "2", last_mic: "Razer Kiyo")   # the Kiyo, unplugged
    expect(c.cameras.map(&:value)).to eq %w[ 0 1 ]
    expect(c.camera).to eq "0"
    expect(c.mic).to eq "MacBook Neo Microphone"           # camera 0's own
  end

  it "keeps the last choice when it is still there, and a stream URL always" do
    expect(choice(last_camera: "1", last_mic: "MacBook Neo Microphone")).to have_attributes(camera: "1", mic: "MacBook Neo Microphone")
    expect(choice(last_camera: "http://pi.local:8080/stream")).to have_attributes(camera_url?: true)
    expect(choice(last_mic: CameraProbe::NO_MIC).mic).to eq CameraProbe::NO_MIC
  end

  it "picks the chosen camera's own microphone" do
    expect(choice(last_camera: "1").mic).to eq "Michael's iPhone Microphone"
  end

  it "offers nothing before the first device search" do
    c = choice(probe: nil, last_camera: "0", last_mic: "Razer Kiyo")
    expect(c).to have_attributes(cameras: [], microphones: [], camera: nil, mic: CameraProbe::NO_MIC, found?: false)
  end
end
