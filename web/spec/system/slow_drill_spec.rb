require "rails_helper"

# The slow dry fire timer in a real browser, with the smallest run it allows.
RSpec.describe "Slow dry fire timer" do
  let(:user) { create(:user) }

  before do
    visit new_session_path
    fill_in "Username", with: user.username
    fill_in "PIN", with: "1010"
    click_button "Sign in"
  end

  it "takes a let-down shot again, and saves the run once the shots are fired" do
    visit new_slow_drill_path(shots: 2, string: 10, limit: 5, between: 3)
    click_button "Start"
    expect(page).to have_text("Raise and settle")
    using_wait_time(6) { expect(page).to have_button("Shot") }
    click_button "Let down"
    expect(page).to have_text("1 let down")
    using_wait_time(8) { expect(page).to have_button("Shot") }
    click_button "Shot"
    expect(page).to have_text("1 fired")
    using_wait_time(10) { expect(page).to have_button("Shot") }
    page.send_keys(:space)
    using_wait_time(10) { expect(page).to have_text("Saved: 2 of 2 slow shots in 5 s, 1 let down") }
    expect(user.slow_drills.last).to have_attributes(shots_fired: 2, let_downs: 1)
  end

  it "stops with nothing done and saves nothing" do
    visit new_slow_drill_path(shots: 2)
    click_button "Start"
    click_button "Stop"
    expect(page).to have_text("Start a timer")
    expect(user.slow_drills).to be_empty
  end
end
