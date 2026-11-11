require "rails_helper"

RSpec.describe CameraProbe do
  let(:json) do
    { names: [ "MacBook Neo Camera", "Razer Kiyo" ],
      cameras: [ { index: 0, width: 1920, height: 1080, brightness: 113.5, name_hint: "MacBook Neo Camera", preview: "cam_0.jpg" },
                 { index: 1, width: 1920, height: 1080, brightness: 0.0, name_hint: "Razer Kiyo", preview: "cam_1.jpg" } ] }.to_json
  end

  after { FileUtils.rm_rf(described_class.dir) }

  it "runs the engine's cameras.py and keeps what it found" do
    allow(Open3).to receive(:capture3).and_return([ "#{json}\n", "", instance_double(Process::Status, success?: true) ])

    probe = described_class.run!

    expect(Open3).to have_received(:capture3).with(EngineRunner.python, "cameras.py", "--json", described_class.dir.to_s, chdir: anything)
    expect(probe.cameras.map(&:label)).to eq [ "MacBook Neo Camera", "Razer Kiyo" ]
    expect(probe.cameras.second).to be_dark
    expect(described_class.latest.cameras.size).to eq 2
  end

  it "reports why it failed" do
    allow(Open3).to receive(:capture3).and_return([ "", "Traceback...\nno camera\n", instance_double(Process::Status, success?: false) ])
    expect { described_class.run! }.to raise_error(CameraProbe::Failed, "no camera")
  end

  it "only serves preview files it made" do
    expect(described_class.preview_path(0)).to be_nil
    expect { described_class.preview_path("../../etc/passwd") }.to raise_error(ArgumentError)
  end
end
