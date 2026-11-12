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
end
