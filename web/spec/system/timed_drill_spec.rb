require "rails_helper"

# The timed-fire timer in a real browser, with the shortest run it allows.
RSpec.describe "Timed fire timer" do
  let(:user) { create(:user) }

  before do
    stub_const("TimedDrill::LEAD_IN_SECONDS", 2)   # 10 in use; short here, still run
    visit new_session_path
    fill_in "Username", with: user.username
    fill_in "PIN", with: "1010"
    click_button "Sign in"
  end

  it "runs a string from ready to the stop beep and saves it" do
    visit new_timed_drill_path(strings: 1, seconds: 5, shots: 5)
    click_button "Start"
    expect(page).to have_text("Starting soon. Get into position.")
    using_wait_time(4) { expect(page).to have_text("Ready. Low ready, wait for the beep.") }
    expect(page).to have_text("String 1 of 1")
    using_wait_time(10) { expect(page).to have_css("[data-phase=fire]") }
    expect(page).to have_text(/Shot \d of 5/)
    using_wait_time(10) { expect(page).to have_text("Saved: 1 of 1 strings of 5 in 5 s") }
    expect(user.timed_drills.last).to have_attributes(strings_done: 1)
  end

  it "stops with nothing fired and saves nothing" do
    visit new_timed_drill_path(strings: 2, seconds: 5)
    click_button "Start"
    click_button "Stop"
    expect(page).to have_text("Start a timer")
    expect(user.timed_drills).to be_empty
  end
end
