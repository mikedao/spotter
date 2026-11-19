require "rails_helper"

RSpec.describe "Hold drills" do
  let(:user) { create(:user) }
  let(:result) { { reps: "10", hold_seconds: "8", rest_seconds: "20", reps_done: "9", let_downs: "1", held_seconds: "77.5" } }

  before { sign_in(user) }

  it "starts with default settings and an empty history" do
    get hold_drills_path
    expect(response.body).to include("Start a drill", "Open the timer", "None yet")
    expect(response.body).to include('value="10"', 'value="8"', 'value="20"')
  end

  it "opens the timer with the settings in the url, clamped" do
    get new_hold_drill_path(reps: 5, hold: 12, rest: 999)
    expect(response.body).to include("5 holds of 12 seconds, 120 seconds rest")
    expect(response.body).to include('data-hold-drill-reps-value="5"', 'data-hold-drill-hold-value="12"')
  end

  it "gives the timer its cues in the user's Kokoro voice, from the exported pieces" do
    user.update!(voice: "bm_george")
    get new_hold_drill_path
    cues = JSON.parse(CGI.unescapeHTML(response.body[/data-hold-drill-cues-value="(.*?)"/, 1]))
    expect(cues.keys).to eq(HoldDrill::CUES)
    expect(cues["raise"]).to eq("/voice-pieces/bm_george/raise.m4a")
    expect(response.body).to include("George")
  end

  it "follows the voice picked in Settings even with a personality on, which has its own" do
    user.update!(voice: "bm_george", personality: "katey")
    expect(Voice.for(user).id).to eq("af_nicole")   # the announcer's: Katey's
    get new_hold_drill_path
    expect(response.body).to include("/voice-pieces/bm_george/raise.m4a")
    expect(response.body).not_to include("/voice-pieces/af_nicole/")
  end

  it "saves what the timer reports, and lists it" do
    post hold_drills_path, params: { hold_drill: result }
    expect(response).to redirect_to(hold_drills_path)
    drill = user.hold_drills.last
    expect(drill).to have_attributes(reps: 10, reps_done: 9, let_downs: 1, held_seconds: 77.5, plan_week: nil)

    get hold_drills_path
    expect(response.body).to include("9 of 10 holds of 8 s, 1 let down")
  end

  it "refuses nonsense without saving" do
    post hold_drills_path, params: { hold_drill: result.merge(reps_done: "0", let_downs: "0", held_seconds: "0") }
    expect(user.hold_drills).to be_empty
    expect(flash[:alert]).to include("No holds to save")
  end

  it "ties a drill to a plan day for someone following the plan, and goes back to the day" do
    user.create_plan_enrollment!(started_on: Time.zone.today)
    get new_hold_drill_path(reps: 10, hold: 8, plan_day: "1-1")
    expect(response.body).to include("Week 1 · Day 1", 'name="plan_day"')

    post hold_drills_path, params: { hold_drill: result, plan_day: "1-1" }
    expect(response).to redirect_to(plan_workout_path(1, 1))
    expect(user.hold_drills.last).to have_attributes(plan_week: 1, plan_day: 1)

    get plan_workout_path(1, 1)
    expect(response.body).to include("Hold drills done for this day", "9 of 10 holds")
  end

  it "ignores a plan day for someone who is not on the plan, or one that does not exist" do
    post hold_drills_path, params: { hold_drill: result, plan_day: "1-1" }
    expect(user.hold_drills.last.plan_week).to be_nil

    user.create_plan_enrollment!(started_on: Time.zone.today)
    post hold_drills_path, params: { hold_drill: result, plan_day: "99-1" }
    expect(user.hold_drills.last.plan_week).to be_nil
  end

  it "offers the timer on a plan day's hold blocks, set to that block" do
    user.create_plan_enrollment!(started_on: Time.zone.today)
    get plan_workout_path(1, 1)
    expect(CGI.unescapeHTML(response.body)).to include("Start the timer: 10 × 8 s", "reps=10", "hold=8", "plan_day=1-1")
    get plan_workout_path(1, 7)
    expect(response.body).not_to include("Start the timer")
  end

  describe "marking done" do
    before { user.create_plan_enrollment!(started_on: Time.zone.today) }   # day 1: ten holds of 8 s

    def drill(**attrs)
      user.hold_drills.create!({ reps: 10, hold_seconds: 8, rest_seconds: 20, reps_done: 10, held_seconds: 80,
                                 plan_week: 1, plan_day: 1, performed_at: Time.current }.merge(attrs))
    end

    it "ticks the hold block of the plan day once a full drill is saved, and offers it again" do
      get plan_workout_path(1, 1)
      expect(response.body).not_to include("✓ done")

      post hold_drills_path, params: { hold_drill: result.merge(reps_done: "10", let_downs: "0"), plan_day: "1-1" }
      get plan_workout_path(1, 1)
      expect(response.body).to include("✓ done")
      expect(CGI.unescapeHTML(response.body)).to include("Do it again: 10 × 8 s")
    end

    it "counts holds let down as attempted, and longer holds as the block" do
      drill(reps_done: 7, let_downs: 3, held_seconds: 70)
      expect(drill(hold_seconds: 10, held_seconds: 100, plan_day: 3)).to be_present   # another day
      get plan_workout_path(1, 1)
      expect(response.body).to include("✓ done")
    end

    it "does not tick it for a drill stopped early, or for shorter holds" do
      drill(reps_done: 4, held_seconds: 32)
      drill(hold_seconds: 5, held_seconds: 50)
      get plan_workout_path(1, 1)
      expect(response.body).not_to include("✓ done")
    end
  end

  describe "in the Journal's sessions" do
    def session_with(rings, at:)
      create(:practice_session, user:, started_at: at, status: "ended", ended_at: at + 1.hour).tap do |s|
        card = create(:card, practice_session: s)
        rings.each_with_index { |r, i| create(:shot, card:, ring: r, decimal_score: r + 0.3, fired_at: at + i.minutes) }
      end
    end

    before do
      session_with([ 9 ] * 20, at: 3.days.ago)
      session_with([ 10 ] * 20, at: 1.day.ago)
      user.hold_drills.create!(reps: 10, hold_seconds: 8, rest_seconds: 20, reps_done: 9, let_downs: 1, held_seconds: 77,
                               performed_at: 2.days.ago)
    end

    it "lists a hold drill between the sessions it fell between, newest first" do
      get journal_path
      body = response.body
      expect(body).to include("Hold drill")
      expect(body).to include("9 of 10 holds of 8 s, 1 let down")
      dates = body[/<tbody.*<\/tbody>/m].scan(/>([A-Z][a-z]{2} \d+, \d\d:\d\d)</).flatten
      expect(dates.size).to eq(3)
      expect(dates).to eq(dates.sort_by { Time.zone.parse("#{it} #{Time.zone.today.year}") }.reverse)
    end

    it "leaves them out when a filter they don't have is chosen" do
      get journal_path(kind: "match")
      expect(response.body).not_to include("9 of 10 holds of 8 s")
    end
  end

  it "keeps each user's drills to themselves" do
    create(:user).hold_drills.create!(reps: 10, hold_seconds: 8, rest_seconds: 20, reps_done: 10, held_seconds: 80, performed_at: Time.current)
    get hold_drills_path
    expect(response.body).to include("None yet")
  end

  it "shows the drills in the Journal, once there are some" do
    get journal_path
    expect(response.body).not_to include("Steadiness")

    post hold_drills_path, params: { hold_drill: result }
    get journal_path
    expect(response.body).to include("Steadiness", "Time held", "Start a drill")
  end
end
