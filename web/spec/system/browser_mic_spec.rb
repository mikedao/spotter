require "rails_helper"

# This browser as the microphone, in a real browser with Chrome's fake microphone
# (a 20 ms beep twice a second: loud, but too short to be a shot).
RSpec.describe "This browser's microphone" do
  let(:user) { create(:user, last_camera: "1", last_mic: CameraProbe::BROWSER_MIC) }

  before { driven_by :cuprite_mic }

  def sign_in_as(user)
    visit new_session_path
    fill_in "Username", with: user.username
    fill_in "PIN", with: "1010"
    click_button "Sign in"
    expect(page).to have_button("New session")
  end

  it "runs the sound check in the page: beeps are too short; a shot unlocks Next and is remembered" do
    sign_in_as(user)
    visit setup_microphone_path(again: 1)

    expect(page).to have_text("Listening - fire when ready", wait: 5)
    expect(page).to have_css("td", text: "too short", wait: 5)
    expect(page).to have_text("0 sounds would trigger")
    expect(page).to have_no_link("Next: start")

    # a shot, as the detector would report one
    page.execute_script(<<~JS)
      const el = document.querySelector("[data-controller='browser-listen']")
      window.Stimulus.getControllerForElementAndIdentifier(el, "browser-listen").sound({ over_db: 68.2, len_ms: 300, ago_ms: 0 })
    JS
    expect(page).to have_link("Next: start")
    expect(page).to have_css("td", text: "would trigger")
    Timeout.timeout(5) { sleep 0.1 until user.reload.sound_check }   # the page reports it in the background
    expect(user.sound_check).to include("mic" => "browser", "loudest_db" => 68.2)
    page.save_screenshot(Rails.root.join("tmp/screenshots/browser_sound_check.png")) if ENV["SCREENSHOTS"]
  end

  it "re-judges what it heard when the trigger level moves, and passes at the new level" do
    sign_in_as(user)
    visit setup_microphone_path(again: 1)
    expect(page).to have_text("Listening - fire when ready", wait: 5)

    # a shot the laptop heard a little quietly (session 10: +58..+62 dB)
    page.execute_script(<<~JS)
      const el = document.querySelector("[data-controller='browser-listen']")
      window.Stimulus.getControllerForElementAndIdentifier(el, "browser-listen").sound({ over_db: 58.4, len_ms: 320, ago_ms: 0 })
    JS
    expect(page).to have_css("td", text: "too quiet")
    expect(page).to have_no_link("Next: start")

    fill_in "Trigger level", with: "56"
    find_field("Trigger level").send_keys(:tab)   # change -> saved
    expect(page).to have_text("Saved")
    expect(page).to have_css("td", text: "would trigger")
    expect(page).to have_link("Next: start")
    Timeout.timeout(5) { sleep 0.1 until user.reload.sound_check }
    expect(user.trigger_levels).to eq("browser" => 56.0)
    expect(user.sound_check).to include("trigger_db" => 56.0, "loudest_db" => 58.4)
    page.save_screenshot(Rails.root.join("tmp/screenshots/browser_trigger_level.png")) if ENV["SCREENSHOTS"]
  end

  it "listens on the range screen and sends each sharp sound to the engine" do
    session = create(:practice_session, user:, status: "shooting", mic: CameraProbe::BROWSER_MIC, stream_port: 1)
    allow(EngineRunner).to receive(:reconcile!)
    allow(EngineRunner).to receive(:snapshot).and_return(nil)
    sent = Queue.new
    allow(EngineRunner).to receive(:trigger!) { |_s, **sound| sent << sound; true }

    sign_in_as(user)
    visit practice_session_path(session)
    expect(page).to have_button("🎤 Listening", wait: 5)

    sound = Timeout.timeout(5) { sent.pop }
    expect(sound[:over_db].to_f).to be > SoundTrigger::DB   # loud - the engine still says "too short"
    expect(sound[:len_ms].to_f).to be < SoundTrigger::MS
    expect(sound[:ago_ms].to_f).to be_between(0, 1000)
  end
end
