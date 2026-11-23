require "rails_helper"

# The Practice page's numbers: days trained this week, the streak, when each kind
# of training was last done.
RSpec.describe PracticeHome do
  let(:user) { create(:user) }
  let(:today) { Date.new(2026, 11, 23) }

  def session_on(date) = create(:practice_session, user:, started_at: date.in_time_zone.change(hour: 18))
  def hold_on(date) = user.hold_drills.create!(reps: 10, hold_seconds: 8, rest_seconds: 20, reps_done: 10,
                                               held_seconds: 80, performed_at: date.in_time_zone.change(hour: 7))

  it "counts any training day, live or dry, and the days in a row" do
    session_on(today - 1)
    hold_on(today - 1)          # the same day counts once
    hold_on(today - 2)
    session_on(today - 3)
    session_on(today - 5)       # a gap before this one
    session_on(today - 10)      # outside the week

    home = described_class.new(user, today:)
    expect(home.days_trained).to eq(4)
    expect(home.streak).to eq(3)          # today isn't over: counted back from yesterday
    expect(home.trained_today?).to be false

    hold_on(today)
    home = described_class.new(user, today:)
    expect(home.streak).to eq(4)
    expect(home.trained_today?).to be true
  end

  it "knows when each kind was last done, and nothing for a new shooter" do
    home = described_class.new(user, today:)
    expect(home.last_at(:session)).to be_nil
    expect(home.streak).to eq(0)
    expect(home.recent_pace).to be_nil

    session_on(today - 4)
    newer = session_on(today - 2)
    hold_on(today - 6)
    home = described_class.new(user, today:)
    expect(home.last(:session)).to eq(newer)
    expect(home.last_at(:hold).to_date).to eq(today - 6)
    expect(home.last_at(:slow)).to be_nil
  end

  it "tells the shooter's own running session from someone else's" do
    mine = create(:practice_session, user:, ended_at: nil)
    theirs = create(:practice_session, ended_at: nil)
    expect(described_class.new(user, running: mine).live_session).to eq(mine)
    expect(described_class.new(user, running: theirs)).to have_attributes(live_session: nil, someone_else_shooting: theirs)
  end
end
