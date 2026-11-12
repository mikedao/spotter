require "rails_helper"

RSpec.describe CardStats do
  let(:spec) { TargetSpec.fetch(:pistol) }
  let(:card) { create(:card) }

  def shot(x, y, ring:, decimal:, **attrs)
    create(:shot, card:, x_mm: x, y_mm: y, ring:, decimal_score: decimal, **attrs)
  end

  it "totals, averages, and finds the group's centre, size and mean radius" do
    shots = [ shot(-10, 0, ring: 9, decimal: 9.2), shot(10, 0, ring: 9, decimal: 9.4), shot(0, 6, ring: 10, decimal: 10.1) ]
    stats = described_class.new(shots, spec)

    expect(stats.total).to eq 28
    expect(stats.decimal_total).to eq 28.7
    expect(stats.mean_point).to eq [ 0.0, 2.0 ]
    expect(stats.mean_point_direction).to eq "high"
    expect(stats.group_size_mm).to eq 20.0
    expect(stats.mean_radius_mm).to be_within(0.05).of((Math.hypot(10, 2) * 2 + 4) / 3)
  end

  it "scores in whole rings when the session does (pistol), decimals otherwise" do
    shots = [ shot(-10, 0, ring: 9, decimal: 9.2), shot(10, 0, ring: 9, decimal: 9.4), shot(0, 6, ring: 10, decimal: 10.1) ]
    rings = described_class.new(shots, spec, whole_rings: true)
    expect([ rings.score, rings.score_average ]).to eq([ 28, 9.33 ])
    decimals = described_class.new(shots, spec)
    expect([ decimals.score, decimals.score_average ]).to eq([ 28.7, 9.57 ])
  end

  it "is scored in whole rings for pistol practice and matches, decimals for rifle and finals" do
    expect(build(:practice_session, target: "pistol").whole_rings?).to be(true)
    expect(build(:practice_session, target: "pistol", course: "match").whole_rings?).to be(true)
    expect(build(:practice_session, target: "pistol", course: "final").whole_rings?).to be(false)
    expect(build(:practice_session, target: "rifle").whole_rings?).to be(false)
  end

  it "counts the shooter's call over the rules' proposal" do
    s = shot(-28, 0, ring: 6, decimal: 6.9)
    s.record_call!(ring: 7)
    expect(described_class.new([ s ], spec).total).to eq 7
  end

  it "re-scores from a tapped position" do
    s = shot(-28, 0, ring: 6, decimal: 6.9)
    s.record_call!(ring: 7, x_mm: -26.0, y_mm: 0.0)
    expect(s.final_decimal).to eq spec.score(26.0).decimal
    expect(s.final_x_mm).to eq(-26.0)
    expect(s.ring).to eq 6   # the proposal is kept
  end
end
