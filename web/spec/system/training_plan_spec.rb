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
    expect(page).to have_button("Start the session: Slow groups")
    expect(page).to have_button("Start the session: Steady-pace series")
    shot("plan_day")

    click_button "Mark done"
    # The post composer comes up; nothing is posted without Post.
    expect(page).to have_text("Post the day to CompetitiveShooter.org")
    expect(page).to have_css("img[src*='/share/day']")
    find("label", text: "Crimson").click
    expect(page).to have_css("img[src*='colors=crimson']", count: 2)
    fill_in "Headline", with: "My day"
    expect(page).to have_css("img[src*='headline=My+day']", count: 2)
    shot("plan_composer")
    click_link "Not now"
    expect(page).to have_button("Not done after all")

    click_link "← Training plan"
    expect(page).to have_text("1 of 84 workouts done")
    shot("plan_done")
  end

  it "shows today's workout above New session on Practice" do
    user.create_plan_enrollment!(started_on: Time.zone.today)
    visit practice_sessions_path
    expect(page).to have_text("Today's training")
    expect(page).to have_button("New session")
    shot("plan_practice")
  end

  it "swaps two days by tapping Swap on each, and by dragging one onto the other" do
    user.create_plan_enrollment!(started_on: Time.zone.today)
    visit training_plan_path
    within("li[data-ref='1-1']") { click_button "⇄ Swap" }
    expect(page).to have_text("Now tap Swap on the day")
    within("li[data-ref='1-2']") { click_button "⇄ Swap" }
    expect(page).to have_text("Swapped.")
    expect(user.plan_enrollment.reload.order.first(2)).to eq(%w[1-2 1-1])
    expect(find("details[open] li", match: :first)["data-ref"]).to eq("1-2")

    page.execute_script(<<~JS)
      const a = document.querySelector("li[data-ref='1-2']"), b = document.querySelector("li[data-ref='1-3']")
      const data = new DataTransfer()
      a.dispatchEvent(new DragEvent("dragstart", { bubbles: true, dataTransfer: data }))
      b.dispatchEvent(new DragEvent("dragover", { bubbles: true, cancelable: true, dataTransfer: data }))
      b.dispatchEvent(new DragEvent("drop", { bubbles: true, cancelable: true, dataTransfer: data }))
    JS
    expect(page).to have_text("Swapped.")
    expect(user.plan_enrollment.reload.order.first(3)).to eq(%w[1-3 1-1 1-2])
    shot("plan_swapped")
  end
end
