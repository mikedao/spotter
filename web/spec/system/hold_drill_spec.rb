require "rails_helper"

# The hold drill timer in a real browser, with the shortest drill it allows.
RSpec.describe "Hold drill timer" do
  let(:user) { create(:user) }

  before do
    visit new_session_path
    fill_in "Username", with: user.username
    fill_in "PIN", with: "1010"
    click_button "Sign in"
  end

  def shot(name) = (page.save_screenshot(Rails.root.join("tmp/screenshots/#{name}.png")) if ENV["SCREENSHOTS"])

  it "runs a hold, lets one down, and saves the result" do
    visit new_hold_drill_path(reps: 2, hold: 3, rest: 5)
    expect(page).to have_button("Start")
    shot("hold_ready")

    click_button "Start"
    expect(page).to have_text("Raise and settle")
    expect(page).to have_text("Hold 1 of 2")
    expect(page).to have_button("Pause")
    shot("hold_settle")

    using_wait_time(6) { expect(page).to have_css("[data-phase=hold]") }
    shot("hold_holding")
    click_button "Let down"
    expect(page).to have_text("Rest. Gun down.")
    expect(page).to have_no_button("Let down")

    using_wait_time(10) { expect(page).to have_text("Hold 2 of 2") }
    using_wait_time(10) { expect(page).to have_text("Saved: 1 of 2 holds of 3 s, 1 let down") }
    expect(user.hold_drills.last).to have_attributes(reps_done: 1, let_downs: 1)
    shot("hold_saved")
  end

  it "can fetch and decode every cue in the user's voice" do
    visit new_hold_drill_path(reps: 2, hold: 3, rest: 5)
    page.execute_script(<<~JS)
      window.cueCheck = "pending"
      const cues = JSON.parse(document.querySelector("[data-controller~=hold-drill]").dataset.holdDrillCuesValue)
      const ctx = new AudioContext()
      Promise.all(Object.values(cues).map((url) => fetch(url).then((r) => r.arrayBuffer()).then((b) => ctx.decodeAudioData(b))))
        .then((buffers) => { window.cueCheck = "ok " + buffers.length }).catch((e) => { window.cueCheck = String(e) })
    JS
    result = 100.times.lazy.map { sleep 0.1; page.evaluate_script("window.cueCheck") }.find { it != "pending" }
    expect(result).to eq("ok #{HoldDrill::CUES.size}")
  end

  it "stops with nothing held and saves nothing" do
    visit new_hold_drill_path(reps: 2, hold: 3, rest: 5)
    click_button "Start"
    click_button "Stop"
    expect(page).to have_text("Start a drill")
    expect(user.hold_drills).to be_empty
  end

  it "pauses and resumes" do
    visit new_hold_drill_path(reps: 1, hold: 3, rest: 5)
    click_button "Start"
    click_button "Pause"
    expect(page).to have_text("Paused")
    expect(page).to have_button("Resume")
    click_button "Resume"
    expect(page).to have_text("Raise and settle")
  end
end
