require "rails_helper"

# The journal's per-session numbers: whole rings, competition shots only.
RSpec.describe SessionSummary do
  let(:session) { create(:practice_session) }

  def shoot(rings, **attrs)
    card = create(:card, practice_session: session)
    rings.each { create(:shot, card:, ring: it, decimal_score: it + 0.4, **attrs) }
  end

  it "scales whole rings to 60 shots and splits complete 10-shot series" do
    shoot([ 10, 9, 9, 10, 8, 9, 10, 9, 9, 9 ] + [ 10, 10, 9, 9, 9, 10, 10, 9, 9, 9 ] + [ 8, 8, 9 ])
    s = described_class.new(session)
    expect(s.count).to eq(23)
    expect(s.total).to eq(92 + 94 + 25)
    expect(s.per_60).to eq((211 * 60 / 23.0).round)   # 550
    expect(s.series).to eq([ 92, 94 ])                   # the 3 left over aren't a series
    expect([ s.worst_series, s.best_series, s.mean_series ]).to eq([ 92, 94, 93.0 ])
    expect(s.tens).to eq(7)
    expect(s.tens_per_60).to eq((7 * 60 / 23.0).round(1))
  end

  it "leaves out sighters, scores a penalized shot 0, and uses your call" do
    shoot([ 7 ] * 3, stage: "sighter")
    shoot([ 10 ] * 9)
    create(:shot, card: session.cards.last, ring: 9, decimal_score: 9.5, penalty: "out of time")
    session.shots.where(ring: 10).first.update!(call_ring: 9)
    s = described_class.new(session.reload)
    expect(s.count).to eq(10)
    expect(s.series).to eq([ 89 ])   # 8 tens, a called 9, a penalized 0
  end

  it "doesn't chart a session under 10 shots" do
    shoot([ 10 ] * 9)
    expect(described_class.new(session).per_60).to be_nil
  end
end
