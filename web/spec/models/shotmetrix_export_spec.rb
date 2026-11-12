require "rails_helper"

# A session as Shotmetrix codes: what goes in, decrypted with a test key.
RSpec.describe ShotmetrixExport do
  let(:session) { create(:practice_session, started_at: 1.hour.ago) }
  let(:card) { create(:card, practice_session: session) }

  # Decrypt a code made for a test key pair: the plaintext's shots.
  def decode(url, priv)
    alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    bits = url.delete_prefix(ShotmetrixCode::URL_PREFIX).chars.map { alphabet.index(it).to_s(2).rjust(5, "0") }.join
    block = [ bits[0, 973 * 8] ].pack("B*")
    eph = block.byteslice(1, 32)
    shared = priv.derive(OpenSSL::PKey.new_raw_public_key("X25519", eph))
    okm = OpenSSL::KDF.hkdf(shared, salt: eph + priv.raw_public_key, info: ShotmetrixCode::INFO, length: 44, hash: "SHA256")
    c = OpenSSL::Cipher.new("aes-256-gcm").decrypt
    c.key, c.iv = okm.byteslice(0, 32), okm.byteslice(32, 12)
    c.auth_tag = block.byteslice(-16, 16)
    c.auth_data = "\x01"
    pt = c.update(block.byteslice(33, 924)) + c.final
    count, total = pt.getbyte(32), pt.byteslice(33, 2).unpack1("n")
    shots = (0...count).map do |i|
      w = pt.byteslice(36 + i * 7, 4).unpack1("N")
      { x: (w >> 20) & 0xFFF, value: (w >> 1) & 0x7F, sighter: w & 1 == 1 }
    end
    { discipline: pt.getbyte(30), decimal: pt.getbyte(31) & 1 == 1, count:, total:, shots: }
  end

  before do
    @priv = OpenSSL::PKey.generate_key("X25519")   # a test key pair, so the spec can decrypt what it made
    stub_const("ShotmetrixCode::PUBLIC_KEY", Base64.strict_encode64(@priv.raw_public_key))
  end

  it "sends a pistol practice in whole rings, sighters flagged, penalized as 0 without a position" do
    create(:shot, card:, ring: 8, decimal_score: 8.5, x_mm: 20.0, y_mm: 0.0, stage: "sighter")
    create(:shot, card:, ring: 10, decimal_score: 10.4, x_mm: 2.0, y_mm: 1.0)
    create(:shot, card:, ring: 9, decimal_score: 9.6, x_mm: 10.0, y_mm: 0.0, penalty: "out of time")
    create(:shot, card:, ring: 9, decimal_score: 9.3, x_mm: 0.0, y_mm: 11.0)
    code = decode(described_class.new(session.reload).urls.first, @priv)
    expect(code).to include(discipline: 3, decimal: false, count: 4, total: 190)   # 10 + 0 + 9, sighter left out
    expect(code[:shots].map { it[:value] }).to eq([ 80, 100, 0, 90 ])
    expect(code[:shots].map { it[:sighter] }).to eq([ true, false, false, false ])
    expect(code[:shots][2][:x]).to eq(0x800)   # no position
  end

  it "uses the position's own score for a call too far from it, so the code is accepted" do
    create(:shot, card:, ring: 9, decimal_score: 9.3, x_mm: 0.0, y_mm: 11.0, call_ring: 7)   # 2 rings off
    code = decode(described_class.new(session.reload).urls.first, @priv)
    expect(code[:shots].first[:value]).to eq(90)
  end

  it "sends decimals for rifle, and splits over 120 shots into codes" do
    rifle = create(:practice_session, target: "rifle", started_at: 1.hour.ago)
    c = create(:card, practice_session: rifle)
    125.times { create(:shot, card: c, ring: 10, decimal_score: 10.2, x_mm: 0.5, y_mm: 0.5) }
    urls = described_class.new(rifle.reload).urls
    expect(urls.size).to eq(2)
    expect(decode(urls.first, @priv)).to include(discipline: 1, decimal: true, count: 120)
    expect(decode(urls.last, @priv)[:count]).to eq(5)
  end

  it "gives the same session the same id, so it imports once" do
    create(:shot, card:, ring: 10, decimal_score: 10.4, x_mm: 2.0, y_mm: 1.0)
    ids = 2.times.map { described_class.new(session.reload).send(:id_for, 0) }
    expect(ids.uniq.size).to eq(1)
    expect(described_class.new(create(:practice_session)).send(:id_for, 0)).not_to eq(ids.first)
  end

  it "says so when there's nothing to send" do
    create(:shot, card:, ring: 8, decimal_score: 8.5, x_mm: 20.0, y_mm: 0.0, stage: "sighter")
    expect { described_class.new(session.reload).urls }.to raise_error(ShotmetrixExport::Nothing)
  end
end
