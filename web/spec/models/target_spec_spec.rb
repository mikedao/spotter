require "rails_helper"

# The same reference values scoring.py checks in the engine: the two must agree.
RSpec.describe TargetSpec do
  let(:pistol) { described_class.fetch(:pistol) }
  let(:rifle) { described_class.fetch(:rifle) }

  it "has the air pistol rings verified against a physical card" do
    expect(pistol.ring_radius_mm(10)).to eq 5.75
    expect(pistol.ring_radius_mm(7) * 2).to eq 59.5      # the black
    expect(pistol.ring_radius_mm(1) * 2).to eq 155.5
    expect(pistol.black_radius_mm).to eq 29.75
  end

  it "matches freETarget's AirRifle table" do
    expect(rifle.ring_radius_mm(4) * 2).to eq 30.5
    expect(rifle.ring_radius_mm(1) * 2).to eq 45.5
  end

  context "with the official 4.5 mm gauge" do
    def score(r) = pistol.score(r, mark_mm: 4.5)

    it "reads dead centre as 10.9, an inner ten" do
      s = score(0)
      expect([ s.decimal, s.ring, s.inner_ten ]).to eq [ 10.9, 10, true ]
    end

    it "gives the higher ring when the hole's edge touches the line" do
      expect(score(5.75 + 2.25)).to have_attributes(decimal: 10.0, ring: 10)
      expect(score(13.75 + 2.25)).to have_attributes(decimal: 9.0, ring: 9)
      expect(score(29.75 + 2.25)).to have_attributes(decimal: 7.0, ring: 7)
      expect(score(77.75 + 2.25)).to have_attributes(decimal: 1.0, ring: 1)
    end

    it "truncates decimals, keeping decimal and ring consistent (6.96 is 6.9, not 7.0)" do
      s = score(29.75 + 2.25 + 0.03)
      expect([ s.decimal, s.ring ]).to eq [ 6.9, 6 ]
    end
  end

  it "uses the 5.8 mm pellet mark by default" do
    expect(pistol.score(13.75 + 2.9).ring).to eq 9
    expect(pistol.score(13.75 + 2.9 + 0.05).ring).to eq 8
  end

  it "names directions as the engine speaks them" do
    expect(described_class.direction(0, 20)).to eq "high"
    expect(described_class.direction(15, 15)).to eq "high right"
    expect(described_class.direction(-14, -12)).to eq "low left"
    expect(described_class.direction(0.3, 0.2)).to eq "centre"
  end
end
