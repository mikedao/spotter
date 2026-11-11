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
