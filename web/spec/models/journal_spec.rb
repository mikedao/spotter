require "rails_helper"

# The journal's headline: distance to the goal and whether it's closing, the
# trend per month and when it reaches the goal, the personal best.
RSpec.describe Journal do
  let(:user) { create(:user) }

  # A session every 3 days with this score per 60 (10 shots of whole rings).
  def sessions(per_60s)
    per_60s.each_with_index do |p, n|
      at = Time.zone.parse("2026-09-01 18:00") + (n * 3).days
      s = create(:practice_session, user:, started_at: at)
      card = create(:card, practice_session: s)
      rings = Array.new(10) { |i| i < (p - 540) / 6 ? 10 : 9 }   # per 60 = 540 + 6 per ten
      rings.each_with_index { |r, i| create(:shot, card:, ring: r, decimal_score: r + 0.2, fired_at: at + i.minutes) }
    end
  end

  it "says how far to the goal and how much closer than the 5 sessions before" do
    sessions([ 540, 540, 546, 540, 546, 552, 552, 558, 552, 558 ])
    j = described_class.new(user)
    expect(j.recent_pace).to eq(554)        # mean of the last 5
    expect(j.previous_pace).to eq(542)      # the 5 before
    expect(j.to_goal).to eq(11)
    expect(j.closing).to eq(12)
    expect(j.personal_best.per_60).to eq(558)
    expect(j.personal_best.started_at).to eq(Time.zone.parse("2026-09-22 18:00"))   # the first time, not the tie
  end

  it "leaves training-plan drills out of the numbers, but counts plan match simulations and still lists every session" do
    sessions([ 540, 552, 558, 546 ])
    drill, baseline, match, _plain = user.practice_sessions.order(:started_at).to_a
    drill.update!(plan_week: 1, plan_day: 1, plan_block: 2)      # Slow groups: a drill
    baseline.update!(plan_week: 1, plan_day: 6, plan_block: 2)   # Baseline simulation (Match simulation)
    match.update!(plan_week: 9, plan_day: 6, plan_block: 2)      # Full match

    j = described_class.new(user)
    expect(j.summaries.size).to eq(4)
    expect(j.charted.map(&:session)).to eq(user.practice_sessions.order(:started_at).to_a.drop(1))
    expect(j.left_out_for_plan).to eq(1)
    expect(j.recent_pace).to eq((552 + 558 + 546) / 3)
    expect(j.personal_best.per_60).to eq(558)
  end

  it "waits for 8 sessions before showing a trend" do
    sessions([ 540, 546, 546, 552, 552, 558, 558 ])
    expect(described_class.new(user).trend_ready?).to be(false)
  end

  it "forecasts the goal from the trend line" do
    sessions([ 540, 546, 546, 552, 552, 558, 558, 564 ])   # every 3 days: ~ +1.05 a day
    j = described_class.new(user)
    expect(j.trend_ready?).to be(true)
    expect(j.trend_per_month).to eq(31.4)
    expect(j.goal_forecast).to eq(Date.new(2026, 9, 24))   # the line is at 563 on Sep 22, +2 takes 2 days
  end

  it "gives no forecast when the trend isn't climbing" do
    sessions([ 558, 552, 552, 546, 546, 540, 540, 540 ])
    j = described_class.new(user)
    expect(j.trend_per_month).to be < 0
    expect(j.goal_forecast).to be_nil
  end

  it "says where the shots land, last 5 sessions against the 5 before (inner tens as X, a penalty as 0)" do
    sessions([ 540, 540, 540, 540, 540, 546, 546, 546, 546, 546 ])   # 0 tens, then 1 ten per card
    Shot.where(ring: 10).first.update!(inner_ten: true)
    Shot.where(ring: 9).last.update!(penalty: "out of time")
    rows = described_class.new(user).landing_rows
    expect(rows.map { it[:label] }).to eq [ "Last 5 sessions", "The 5 before" ]
    expect(rows.map { it[:shots] }).to eq [ 50, 50 ]
    expect(rows.first[:counts]).to eq("X" => 1, "10" => 4, "9" => 44, "8" => 0, "7" => 0, "≤6" => 1)
    expect(rows.last[:counts]).to include("X" => 0, "10" => 0, "9" => 50)
  end

  it "says where the misses (8 or worse) go, by direction, latest first" do
    sessions([ 540 ] * 6)                     # every shot a 9: no misses
    expect(described_class.new(user).miss_rows).to eq []
    Shot.order(:id).last(3).each { it.update!(ring: 8, x_mm: -9.0, y_mm: -9.0) }   # low left
    Shot.order(:id).first.update!(ring: 7, x_mm: 0.0, y_mm: 20.0)                 # high, in the session before
    rows = described_class.new(user).miss_rows
    expect(rows.map { it[:label] }).to eq [ "Last 5 sessions", "The 5 before" ]
    expect(rows.first).to include(misses: 3)
    expect(rows.first[:counts]).to include("low left" => 3, "high" => 0)
    expect(rows.last[:counts]).to include("high" => 1)
  end

  it "charts each series number across sessions (only numbers 2 sessions reached)" do
    sessions([ 540, 546 ])                    # one 10-shot series each: 90, 91
    s = create(:practice_session, user:, started_at: Time.zone.parse("2026-09-10 18:00"))
    card = create(:card, practice_session: s)
    20.times { |i| create(:shot, card:, ring: i < 10 ? 8 : 10, decimal_score: 9.0, fired_at: s.started_at + i.minutes) }
    points = described_class.new(user).series_by_number_points
    expect(points.map { it[:label] }).to eq [ "Series 1" ]       # series 2: only one session
    expect(points.first).to include(y: 87.0, low: 80, high: 91)
  end

  it "times each shot from the one before on the same card, leaving out card changes and pauses" do
    s = create(:practice_session, user:, started_at: Time.zone.parse("2026-09-10 18:00"))
    card1, card2 = create(:card, practice_session: s, number: 1), create(:card, practice_session: s, number: 2)
    t = s.started_at
    # card 1: 10 shots 22 s apart, then a 5-minute pause, one more
    10.times { |i| create(:shot, card: card1, ring: 9, decimal_score: 9.2, fired_at: t + (i * 22).seconds) }
    create(:shot, card: card1, ring: 6, decimal_score: 6.1, fired_at: t + 198.seconds + 5.minutes)
    # card 2: two minutes later (the card change), then 15 s
    create(:shot, card: card2, ring: 10, decimal_score: 10.1, fired_at: t + 198.seconds + 7.minutes)
    create(:shot, card: card2, ring: 7, decimal_score: 7.1, fired_at: t + 213.seconds + 7.minutes)
    j = described_class.new(user)
    expect(j.rhythm.map(&:first)).to eq([ 22.0 ] * 9 + [ 15.0 ])
    expect(j.rhythm_median).to eq 22
    expect(j.rhythm_rows.map { [ it[:label], it[:shots] ] }).to eq [ [ "Under 20 s", 1 ], [ "20–25 s", 9 ] ]
    expect(j.rhythm_rows.first[:counts]).to include("7" => 1)
  end

  it "charts each session's group size, with where its centre was" do
    sessions([ 540, 540 ])
    Shot.order(:id).each_with_index { |shot, i| shot.update!(x_mm: (i % 2) * 10.0 - 5.0, y_mm: -3.0) }   # 10 mm wide, 3 mm low
    points = described_class.new(user).group_points(->(_) { "/x" })
    expect(points.size).to eq 2
    expect(points.first[:y]).to eq 10.0
    expect(points.first[:title]).to include("group 10.0 mm, its centre 3.0 mm low")
  end
end
