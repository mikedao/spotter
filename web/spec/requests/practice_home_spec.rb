require "rails_helper"

# The Practice page, the first page after signing in: a summary, then big
# buttons for what to do today, then the sessions.
RSpec.describe "Practice home" do
  let(:user) { create(:user) }

  before { sign_in(user) }

  def body = CGI.unescapeHTML(response.body)

  it "offers every kind of training, each with when it was last done" do
    user.hold_drills.create!(reps: 10, hold_seconds: 8, rest_seconds: 20, reps_done: 10, held_seconds: 80, performed_at: Time.current)
    get practice_sessions_path
    expect(body).to include("What are we doing today?", "New session", "Hold drills", "Slow dry fire", "Timed fire", "Journal")
    expect(body).to include("Last: today", "Not tried yet")
    expect(body).to include(hold_drills_path, slow_drills_path, timed_drills_path, journal_path, setup_path)
    expect(body).to include("Training plan", "Twelve weeks")      # not on the plan: a way to it
    expect(body).to include("Last session", "Recent pace", "This week", "1 of 7", "trained today")
  end

  it "puts today's plan day first, and New session second" do
    user.create_plan_enrollment!(started_on: Time.zone.today)
    get practice_sessions_path
    expect(body).to include("Today's training", "Open today's workout", "of 84")
    expect(body.index("plan-today")).to be < body.index("New session")
  end

  it "sends the shooter back to a running session instead of a new one" do
    live = create(:practice_session, user:, ended_at: nil)
    allow(EngineRunner).to receive(:running).and_return(live)
    get practice_sessions_path
    expect(body).to include("Back to the range screen", practice_session_path(live))
    expect(body).not_to include(">New session<")
  end

  it "says who is shooting when it is someone else" do
    other = create(:practice_session, user: create(:user, name: "Sam"), ended_at: nil)
    allow(EngineRunner).to receive(:running).and_return(other)
    get practice_sessions_path
    expect(body).to include("Sam", "is shooting", "One session at a time")
    expect(body).not_to include(setup_path)
  end

  it "puts the buttons above the summary" do
    get practice_sessions_path
    expect(body.index("What are we doing today?")).to be < body.index("Lately")
  end

  it "lists the latest 5 sessions, and the rest under Show all" do
    sessions = Array.new(7) { |n| create(:practice_session, user:, status: "ended", started_at: Time.zone.parse("2026-11-01 18:00") + n.days, ended_at: Time.zone.parse("2026-11-01 19:00") + n.days) }
    get practice_sessions_path
    expect(body).to include("Show all 7 sessions", "Trends in the Journal")
    details = body.index("<details")
    expect(sessions.last(5).map { body.index(it.title) }).to all(be < details)
    expect(sessions.first(2).map { body.index(it.title) }).to all(be > details)   # still there, with their Delete
    expect(body.scan(/aria-label="Delete /).size).to eq(7)
  end

  it "has no Show all with 5 sessions or fewer" do
    create(:practice_session, user:, status: "ended", ended_at: Time.current)
    get practice_sessions_path
    expect(body).not_to include("Show all")
  end
end
