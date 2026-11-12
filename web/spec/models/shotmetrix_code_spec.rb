require "rails_helper"

# The Shotmetrix QR encoder against Shotmetrix's own published test vectors.
RSpec.describe ShotmetrixCode do
  vectors = JSON.parse(Rails.root.join("spec/fixtures/files/shotmetrix/test-vectors.json").read)

  def shots_of(vector) = vector["shots"].map { it.transform_keys(&:to_sym) }

  def args_of(vector, now)
    { discipline: vector["discipline"], decimal: vector["decimal"], time: vector["time"], shots: shots_of(vector),
      app: vector["app"] || 0, now: }
  end

  vectors["valid"].each do |v|
    it "builds #{v['name']} byte for byte" do
      pt = described_class.plaintext(**args_of(v, vectors["now"]), app_secret: v["app_secret"],
                                     id: [ v["id_hex"] ].pack("H*"), fill: "\0" * 840)
      expect(pt.unpack1("H*")).to eq(v["plaintext_hex"])

      sealed = described_class.seal(pt, vectors["test_public_key"], ephemeral_private: [ v["ephemeral_private_hex"] ].pack("H*"))
      expect(described_class.base32(sealed)).to eq(v["code"])
      expect(vectors["url_prefix"] + v["code"]).to eq(v["url"])
      expect(v["code"].size).to eq(1557)
    end
  end

  vectors["input_errors"].each do |v|
    it "refuses #{v['name']}: #{v['error']}" do
      expect { described_class.plaintext(**args_of(v, vectors["now"])) }.to raise_error(ShotmetrixCode::Invalid, v["error"])
    end
  end

  it "makes a fresh, full-size code with the real key" do
    url = described_class.url(discipline: 3, decimal: false, time: Time.current - 1.hour,
                              shots: [ { x: 1.0, y: -2.0, value: 10 }, { x: -9.0, y: 3.0, value: 9 } ])
    expect(url).to start_with("https://shotmetrix.com/api/qrcode/")
    expect(url.delete_prefix("https://shotmetrix.com/api/qrcode/")).to match(/\A[A-Z2-7]{1557}\z/)
  end
end
