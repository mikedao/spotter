require "rails_helper"

# The rig setup page with both checks' results, in a real browser.
RSpec.describe "Rig setup" do
  let(:user) { create(:user, name: "Mike", last_mic: "Razer Kiyo") }

  before do
    FileUtils.mkdir_p(RigCheck::Locate.dir)
    FileUtils.cp(Rails.root.join("public/icon.png"), RigCheck::Locate.overlay_path(user))
    RigCheck::Locate.result_path(user).write({
      found: true, camera: "1", view_deg: 26.0, edge_rms_px: 0.41, perspective: true, ring_rms_mm: 0.157, rings: 10,
      flat_worst_mm: -0.43, flat_worst_at: [ 7, 225 ], mm_per_px: 0.197, ring1_offscreen: [], brightness: 67, saturated_pct: 0
    }.to_json)
    state = RigCheck::Listen::State.new(
      user_id: user.id, pid: 0, mic: "Razer Kiyo", seconds: 60, started_at: Time.current, trigger_db: 45.0, trigger_ms: 180.0,
      finished: true, summary: { "silent" => false, "floor_dbfs" => -61.0 },
      sounds: [ { "n" => 1, "t" => 3.2, "over_db" => 38.0, "len_ms" => 22, "would_trigger" => false },
                { "n" => 2, "t" => 8.9, "over_db" => 61.3, "len_ms" => 330, "would_trigger" => true } ]
    )
    allow(RigCheck::Listen).to receive(:state_for).and_return(state)
  end

  after { FileUtils.rm_rf(RigCheck::Locate.dir) }

  it "shows the camera verdicts and which sounds would trigger" do
    visit new_session_path
    fill_in "Email", with: user.email_address
    fill_in "Password", with: "range-day-10"
    click_button "Sign in"
    click_on "Rig setup"

    expect(page).to have_text("Ready to shoot")
    expect(page).to have_text("Slightly bowed")
    expect(page).to have_text("would trigger")
    expect(page).to have_text("1 sound would trigger out of 2 heard")
    page.save_screenshot(Rails.root.join("tmp/screenshots/rig_setup.png")) if ENV["SCREENSHOTS"]
  end
end
