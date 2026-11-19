require "rails_helper"

# The training plan in a real browser: start it, open the day, tick it off.
RSpec.describe "Training plan" do
  let(:user) { create(:user) }

  before do
    visit new_session_path
    fill_in "Username", with: user.username
    fill_in "PIN", with: "1010"
    click_button "Sign in"
  end

  def shot(name) = (page.save_screenshot(Rails.root.join("tmp/screenshots/#{name}.png")) if ENV["SCREENSHOTS"])

  it "starts from the menu, opens today's day and ticks it off" do
    visit practice_sessions_path
    find("button[aria-label='Menu']").click
    click_link "Training plan"
    expect(page).to have_button("Start the plan")
    shot("plan_start")

    click_button "Start the plan"
    expect(page).to have_text("Today's training")
    expect(page).to have_text("Routine and groups")
    shot("plan_overview")

    click_link "Open today's workout"
    expect(page).to have_text("Hold drills")
    expect(page).to have_button("Start the session")
    shot("plan_day")

    click_button "Mark done"
    expect(page).to have_text("Done. Nice work.")
    expect(page).to have_button("Not done after all")

    click_link "← Training plan"
    expect(page).to have_text("1 of 72 workouts done")
    shot("plan_done")
  end

  it "shows today's workout above New session on Practice" do
    user.create_plan_enrollment!(started_on: Time.zone.today)
    visit practice_sessions_path
    expect(page).to have_text("Today's training")
    expect(page).to have_button("New session")
    shot("plan_practice")
  end
end
