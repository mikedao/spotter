require "rails_helper"

# The new-session wizard's camera check and sound check with their results, in
# a real browser: both passed, so both Next buttons are unlocked.
RSpec.describe "New session setup checks" do
  let(:user) { create(:user, name: "Mike", last_camera: "1", last_mic: "Razer Kiyo") }

  before do
    FileUtils.mkdir_p(RigCheck::Locate.dir)
    FileUtils.cp(Rails.root.join("public/icon.png"), RigCheck::Locate.overlay_path(user))
    RigCheck::Locate.result_path(user).write({
      found: true, camera: "1", view_deg: 26.0, edge_rms_px: 0.41, perspective: true, ring_rms_mm: 0.157, rings: 10,
      flat_worst_mm: -0.43, flat_worst_at: [ 7, 225 ], mm_per_px: 0.197, ring1_offscreen: [], brightness: 67, saturated_pct: 0,
      sharpness: 772.0, seq: 12
    }.to_json)
    state = RigCheck::LiveProcess::State.new(
      kind: :listen, label: "sound check", user_id: user.id, pid: 0, started_at: Time.current, finished: true,
      data: { "mic" => "Razer Kiyo", "seconds" => 60, "trigger_db" => SoundTrigger::DB, "trigger_ms" => SoundTrigger::MS,
              "summary" => { "silent" => false, "floor_dbfs" => -61.0 },
              "sounds" => [ { "n" => 1, "t" => 3.2, "over_db" => 38.0, "len_ms" => 22, "would_trigger" => false },
                            { "n" => 2, "t" => 8.9, "over_db" => 68.3, "len_ms" => 330, "would_trigger" => true } ] }
    )
    allow(RigCheck::Listen).to receive(:state_for).and_return(state)
  end

  after { FileUtils.rm_rf(RigCheck::Locate.dir) }

  it "shows the camera verdicts and which sounds would trigger, and lets you on" do
    visit new_session_path
    fill_in "Username", with: user.username
    fill_in "PIN", with: "1010"
    click_button "Sign in"
    expect(page).to have_button("New session")
    visit setup_check_path

    expect(page).to have_text("2. Camera check")
    expect(page).to have_text("Ready to shoot")
    expect(page).to have_text("Slightly bowed")
    expect(page).to have_text("Sharpness 772")
    page.save_screenshot(Rails.root.join("tmp/screenshots/setup_check.png")) if ENV["SCREENSHOTS"]
    click_on "Next: microphone"

    expect(page).to have_text("3. Microphone")
    expect(page).to have_text("would trigger")
    expect(page).to have_text("1 sound would trigger out of 2 heard")
    page.save_screenshot(Rails.root.join("tmp/screenshots/setup_microphone.png")) if ENV["SCREENSHOTS"]
    click_on "Next: start"

    expect(page).to have_text("✓ check passed")
    expect(page).to have_text("✓ heard a shot")
    expect(page).to have_button("Start session")
  end
end
