require "rails_helper"

RSpec.describe "Timed fire" do
  let(:user) { create(:user) }
  let(:result) { { strings: "4", shots: "5", string_seconds: "20", rest_seconds: "30", strings_done: "4" } }

  before { sign_in(user) }

  it "starts with default settings and an empty history" do
    get timed_drills_path
    expect(response.body).to include("Start a timer", "Open the timer", "None yet", 'value="4"', 'value="20"', 'value="30"')
  end

  it "opens the timer with the settings in the url, clamped, and the cues in the picked voice" do
    user.update!(voice: "bm_george")
    get new_timed_drill_path(strings: 3, seconds: 10, shots: 5, rest: 999)
    expect(response.body).to include("3 strings of 5 shots in 10 seconds, 120 seconds rest")
    cues = JSON.parse(CGI.unescapeHTML(response.body[/data-timed-drill-cues-value="(.*?)"/, 1]))
    expect(cues.keys).to eq(TimedDrill::CUES)
    expect(cues["ready"]).to eq("/voice-pieces/bm_george/ready.m4a")
  end

  it "saves what the timer reports" do
    post timed_drills_path, params: { timed_drill: result }
    expect(response).to redirect_to(timed_drills_path)
    expect(user.timed_drills.last).to have_attributes(strings_done: 4, string_seconds: 20)
    get timed_drills_path
    expect(response.body).to include("4 of 4 strings of 5 in 20 s")
  end

  it "refuses an empty run" do
    post timed_drills_path, params: { timed_drill: result.merge(strings_done: "0") }
    expect(user.timed_drills).to be_empty
    follow_redirect!
    expect(CGI.unescapeHTML(response.body)).to include("No strings to save")
  end

  describe "from the plan" do
    before { user.create_plan_enrollment!(started_on: Time.zone.today) }

    it "offers the timer on the day's timed block, and marks it done" do
      get plan_workout_path(1, 2)
      body = CGI.unescapeHTML(response.body)
      expect(body).to include("Start the timer: 4 × 5 in 20 s")
      expect(body).to include(new_timed_drill_path(strings: 4, seconds: 20, plan_day: "1-2"))
      expect(body).not_to include("✓ done")

      post timed_drills_path, params: { timed_drill: result, plan_day: "1-2" }
      expect(response).to redirect_to(plan_workout_path(1, 2))
      get plan_workout_path(1, 2)
      expect(CGI.unescapeHTML(response.body)).to include("✓ done", "Do it again: 4 × 5 in 20 s", "Timed fire done for this day")
    end

    it "does not tick a run with fewer strings or more time" do
      post timed_drills_path, params: { timed_drill: result.merge(strings: "2", strings_done: "2"), plan_day: "1-2" }
      get plan_workout_path(1, 2)
      expect(response.body).not_to include("✓ done")
    end
  end

  it "ignores a plan day for someone not on the plan" do
    post timed_drills_path, params: { timed_drill: result, plan_day: "1-2" }
    expect(user.timed_drills.last.plan_ref).to be_nil
  end

  describe "in the Journal" do
    it "shows a section once there is a run, and none before" do
      get journal_path
      expect(response.body).not_to include("Fastest string")

      post timed_drills_path, params: { timed_drill: result }
      post timed_drills_path, params: { timed_drill: result.merge(string_seconds: "10", strings_done: "3") }
      get journal_path
      body = CGI.unescapeHTML(response.body)
      expect(body).to include("Fastest string", "Start the timer", "Strings finished in each timed fire run")
      stats = TimedDrillStats.new(user)
      expect(stats.tiles).to eq([ [ "Runs", "2", "of the timer" ], [ "Strings", "7", "to the stop beep" ],
                                  [ "Shots", "35", "dry, in time" ], [ "Fastest string", "20 s", "in a full run" ] ])
    end

    it "lists runs among the sessions, and leaves them out under a gun or exercise filter" do
      at = 3.days.ago
      create(:practice_session, user:, started_at: at, status: "ended", ended_at: at + 1.hour).tap do |ps|
        card = create(:card, practice_session: ps)
        20.times { |i| create(:shot, card:, ring: 9, decimal_score: 9.3, fired_at: at + i.minutes) }
      end
      user.timed_drills.create!(strings: 4, shots: 5, string_seconds: 20, rest_seconds: 30, strings_done: 4, performed_at: 1.day.ago)
      get journal_path
      expect(CGI.unescapeHTML(response.body)).to include("Timed fire", "4 of 4 strings of 5 in 20 s")
      get journal_path(kind: "match")
      expect(CGI.unescapeHTML(response.body)).not_to include("4 of 4 strings of 5 in 20 s")
    end

    it "follows the period filter and keeps each user's runs to themselves" do
      create(:user).timed_drills.create!(strings: 4, shots: 5, string_seconds: 20, rest_seconds: 30, strings_done: 4, performed_at: Time.current)
      user.timed_drills.create!(strings: 2, shots: 5, string_seconds: 20, rest_seconds: 30, strings_done: 2, performed_at: 400.days.ago)
      expect(TimedDrillStats.new(user)).to be_any
      expect(TimedDrillStats.new(user, days: 30)).not_to be_any
    end
  end
end
