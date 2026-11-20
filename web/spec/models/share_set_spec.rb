require "rails_helper"

RSpec.describe ShareSet do
  let(:user) { create(:user) }

  def finished(**attrs) = create(:practice_session, user:, status: "ended", ended_at: Time.current, **attrs)

  def card_of(session, number, rings, **attrs)
    card = create(:card, practice_session: session, number:)
    rings.each_with_index { |r, i| create(:shot, card:, number: i + 1, ring: r, decimal_score: r + 0.4, x_mm: 3.0 + i, y_mm: -2.0, **attrs) }
    card
  end

  it "counts a pistol practice session in whole rings, its series 10 shots at a time" do
    s = finished
    card_of(s, 1, [ 10 ] * 10)
    card_of(s, 2, [ 9 ] * 10)
    card_of(s, 3, [ 8, 8, 8 ])
    set = ShareSet.find(user, [ s.id ])
    expect(set.total).to eq(214)
    expect(set.out_of).to eq(230)
    expect(set.series.map { [ it.label, it.total, it.complete ] }).to eq([ [ "S1", 100, true ], [ "S2", 90, true ], [ "S3", 24, false ] ])
    expect(set.best_series.label).to eq("S1")
    expect(set.worst_series.label).to eq("S2")
    expect(set.cards.map(&:label)).to eq([ "Card 1", "Card 2", "Card 3" ])
    expect(set.title).to eq("10m Air Pistol · Practice")
  end

  it "leaves sighters out and scores a shot out of time zero" do
    s = finished(course: "match")
    c = create(:card, practice_session: s, number: 1)
    create(:shot, card: c, number: 1, stage: "sighter", ring: 5)
    create(:shot, card: c, number: 2, stage: "match", match_number: 1, series: 1, ring: 9)
    create(:shot, card: c, number: 3, stage: "match", match_number: 2, series: 1, ring: 10, penalty: "out of time")
    set = ShareSet.find(user, [ s.id ])
    expect(set.shots.size).to eq(2)
    expect(set.total).to eq(9)
    expect(set.kind_name).to eq("Match")
  end

  it "counts rifle in decimals, with no 'out of'" do
    s = finished(target: "rifle")
    card_of(s, 1, [ 10, 9 ])
    set = ShareSet.find(user, [ s.id ])
    expect(set.whole_rings?).to be(false)
    expect(set.total_text).to eq(format("%.1f", set.shots.sum(&:final_decimal)))   # rescored from position
    expect(set.total_text).to match(/\A\d+\.\d\z/)
    expect(set.out_of).to be_nil
    expect(set.score_parts.last).to be_nil
  end

  it "joins a day of training: sessions in order, series numbered across them, cards named by day" do
    a = finished(started_at: Time.zone.parse("2026-11-12 09:00"))
    b = finished(started_at: Time.zone.parse("2026-11-13 18:00"))
    card_of(b, 1, [ 9 ] * 10)
    card_of(a, 1, [ 10 ] * 10)
    set = ShareSet.find(user, [ b.id, a.id ])
    expect(set.sessions).to eq([ a, b ])
    expect(set.series.map { [ it.label, it.total ] }).to eq([ [ "S1", 100 ], [ "S2", 90 ] ])
    expect(set.cards.map(&:label)).to eq([ "Nov 12 · Card 1", "Nov 13 · Card 2" ])
    expect(set.date_text).to eq("Nov 12–13, 2026")
    expect(set.meta).to eq("2 sessions · 20 shots")
    expect(set.title).to eq("10m Air Pistol · Training")
  end

  it "refuses a live session, mixed targets, and nothing scored" do
    live = create(:practice_session, user:)
    card_of(live, 1, [ 10 ])
    expect { ShareSet.find(user, [ live.id ]) }.to raise_error(ShareSet::Invalid, /finished/)

    pistol, rifle = finished, finished(target: "rifle")
    card_of(pistol, 1, [ 10 ])
    card_of(rifle, 1, [ 10 ])
    expect { ShareSet.find(user, [ pistol.id, rifle.id ]) }.to raise_error(ShareSet::Invalid, /apart/)

    expect { ShareSet.find(user, [ finished.id ]) }.to raise_error(ShareSet::Invalid, /no scored shots/)
    expect { ShareSet.find(user, []) }.to raise_error(ShareSet::Invalid)
  end

  it "never finds another user's session" do
    other = create(:practice_session, status: "ended", ended_at: Time.current)
    expect { ShareSet.find(user, [ other.id ]) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "sorts misses by direction from the centre" do
    s = finished
    c = create(:card, practice_session: s, number: 1)
    create(:shot, card: c, number: 1, ring: 6, x_mm: 30, y_mm: 0)     # right
    create(:shot, card: c, number: 2, ring: 6, x_mm: 0, y_mm: 30)     # high
    create(:shot, card: c, number: 3, ring: 7, x_mm: -20, y_mm: -20)  # low left
    create(:shot, card: c, number: 4, ring: 10, x_mm: 1, y_mm: 1)     # not a miss
    expect(ShareSet.find(user, [ s.id ]).misses_by_direction).to eq([ 1, 0, 1, 0, 0, 1, 0, 0 ])
  end
end
