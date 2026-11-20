require "rails_helper"

RSpec.describe "Slow dry fire" do
  let(:user) { create(:user) }
  let(:result) { { shots: "30", string_size: "10", limit_seconds: "12", between_seconds: "10", string_rest_seconds: "60", shots_fired: "30", let_downs: "3", break_seconds: "200" } }

  before { sign_in(user) }

  it "starts with default settings and an empty history" do
    get slow_drills_path
    expect(response.body).to include("Start a timer", "Open the timer", "None yet", 'value="12"', 'value="60"')
  end

  it "opens the timer with the settings in the url, clamped, and the cues in the picked voice" do
    user.update!(voice: "bm_george")
    get new_slow_drill_path(shots: 30, limit: 8, between: 1)
    expect(response.body).to include("30 shots in strings of 10, 8 seconds to break each, 3 seconds between shots")
    cues = JSON.parse(CGI.unescapeHTML(response.body[/data-slow-drill-cues-value="(.*?)"/, 1]))
    expect(cues.keys).to eq(SlowDrill::CUES)
    expect(cues["hold"]).to eq("/voice-pieces/bm_george/hold.m4a")
  end

  it "saves what the timer reports, and refuses an empty run" do
    post slow_drills_path, params: { slow_drill: result }
    expect(response).to redirect_to(slow_drills_path)
    expect(user.slow_drills.last).to have_attributes(shots_fired: 30, let_downs: 3)
    post slow_drills_path, params: { slow_drill: result.merge(shots_fired: "0", let_downs: "0") }
    expect(user.slow_drills.count).to eq(1)
  end

  describe "from the plan" do
    before { user.create_plan_enrollment!(started_on: Time.zone.today) }

    it "offers the timer on a slow dry fire block, and marks it done when its shots were fired in time" do
      block = TrainingPlan.day(1, 2).blocks.find { it.slow }
      get plan_workout_path(1, 2)
      body = CGI.unescapeHTML(response.body)
      expect(body).to include("Start the timer: #{block.shots} shots, 12 s each")
      expect(body).to include(new_slow_drill_path(shots: block.shots, limit: 12, plan_day: "1-2"))

      post slow_drills_path, params: { slow_drill: result.merge(shots: block.shots.to_s, shots_fired: (block.shots - 5).to_s), plan_day: "1-2" }
      get plan_workout_path(1, 2)
      expect(response.body).not_to include("✓ done")

      post slow_drills_path, params: { slow_drill: result.merge(shots: block.shots.to_s, shots_fired: block.shots.to_s), plan_day: "1-2" }
      expect(response).to redirect_to(plan_workout_path(1, 2))
      get plan_workout_path(1, 2)
      expect(CGI.unescapeHTML(response.body)).to include("✓ done", "Do it again", "Slow dry fire done for this day")
    end
  end

  describe "in the Journal" do
    it "shows a section and rows once there are runs, and keeps each user's to themselves" do
      get journal_path
      expect(response.body).not_to include("Time to break")
      create(:user).slow_drills.create!(shots: 10, string_size: 10, limit_seconds: 12, between_seconds: 10, string_rest_seconds: 60,
                                        shots_fired: 10, break_seconds: 50, performed_at: Time.current)
      post slow_drills_path, params: { slow_drill: result }
      stats = SlowDrillStats.new(user)
      expect(stats.tiles).to eq([ [ "Runs", "1", "of the timer" ], [ "Shots", "30", "fired in time" ],
                                  [ "First time", "91%", "raises that became a shot" ], [ "Time to break", "6.7 s", "average, from the hold start" ] ])
      get journal_path
      expect(CGI.unescapeHTML(response.body)).to include("Time to break", "Start the timer")
    end
  end
end
