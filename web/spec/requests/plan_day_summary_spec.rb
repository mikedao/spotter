require "rails_helper"

# A finished plan day's page sums up each part of it: every timer and session
# done for each block, with its numbers.
RSpec.describe "A finished training-plan day's summary" do
  let(:user) { create(:user) }

  before do
    sign_in(user)
    user.create_plan_enrollment!(started_on: Time.zone.today)
    # Week 1 day 2: hold drills, slow dry fire, a timed sequence, then the lane (FWB 65).
    user.hold_drills.create!(reps: 10, hold_seconds: 8, rest_seconds: 10, reps_done: 10, held_seconds: 80, plan_week: 1, plan_day: 2, performed_at: Time.current)
    user.slow_drills.create!(shots: 15, string_size: 10, limit_seconds: 12, between_seconds: 10, string_rest_seconds: 60,
                             shots_fired: 15, let_downs: 1, break_seconds: 90, plan_week: 1, plan_day: 2, performed_at: Time.current)
    user.timed_drills.create!(strings: 4, shots: 5, string_seconds: 20, rest_seconds: 30, strings_done: 3, plan_week: 1, plan_day: 2, performed_at: Time.current)
  end

  def page_text = CGI.unescapeHTML(response.body)

  it "shows nothing of the kind before the day is ticked done" do
    get plan_workout_path(1, 2)
    expect(page_text).not_to include("How the day went")
  end

  it "sums up each part once done: every run, what was finished, what wasn't, and the note" do
    lane = TrainingPlan.day(1, 2).blocks.find(&:session)
    session = create(:practice_session, user:, status: "ended", ended_at: Time.current, plan_week: 1, plan_day: 2, plan_block: lane.number)
    card = create(:card, practice_session: session, number: 1)
    [ 10, 9, 9, 8, 10, 9, 10, 9, 9, 10 ].each_with_index { |ring, i| create(:shot, card:, number: i + 1, ring:, decimal_score: ring + 0.2, x_mm: i - 5.0, y_mm: 1.0) }

    patch plan_workout_path(1, 2), params: { done: "1", note: "Trigger felt clean" }
    get plan_workout_path(1, 2)
    text = page_text

    expect(text).to include("How the day went")
    expect(text).to include("Hold drills", "10/10", "10 of 10 holds of 8 s · 80 s held")
    expect(text).to include("Slow dry fire", "15/15", "6.0 s to break", "94% first time")
    expect(text).to include("Timed sequence", "3/4", "Not finished as planned", "3 of 4 strings of 5 in 20 s")
    expect(text).to include("On the lane (FWB 65)", "93 over 10 shots", "avg 9.3")
    expect(response.body).to include(%(href="#{practice_session_path(session)}"))
    expect(text).to include("Your note", "Trigger felt clean")
    expect(text).not_to include("Hold drills done for this day")   # the summary replaces the run lists
  end

  it "says a block was not done when nothing was recorded for it" do
    patch plan_workout_path(1, 2), params: { done: "1" }
    get plan_workout_path(1, 2)
    lane = Nokogiri::HTML(response.body).at_css("li[data-block='#{TrainingPlan.day(1, 2).blocks.find(&:session).number}']")
    expect(lane.text).to include("On the lane (FWB 65)", "Not done")
  end
end
