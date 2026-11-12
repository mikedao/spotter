require "rails_helper"

# Mid-session: "not scored" -> plot it in a panel over the range screen, which
# keeps going (sound stays on).
RSpec.describe "Plotting a shot that wasn't scored, mid-session" do
  let(:user) { create(:user) }

  around do |example|
    ENV["SPOTTER_PYTHON"] = Rails.root.join("spec/fixtures/files/fake_pinpoint.sh").to_s   # the hole at (-9, 3) mm
    example.run
  ensure
    ENV.delete("SPOTTER_PYTHON")
  end

  it "plots it from the range screen without leaving it" do
    session = create(:practice_session, user:, status: "shooting", started_at: 10.minutes.ago)
    card = create(:card, practice_session: session, number: 1)
    create(:shot, card:, number: 1, ring: 9, decimal_score: 9.3, x_mm: 5.0, y_mm: 1.0, fired_at: 5.minutes.ago)
    capture = create(:shot, card:, number: nil, status: "unscored", unscored_reason: "no new hole on the card",
                            x_mm: nil, y_mm: nil, ring: nil, decimal_score: nil, fired_at: 1.minute.ago)
    capture.after_image.attach(io: File.open(Rails.root.join("public/icon.png")), filename: "after.png", content_type: "image/png")
    allow(EngineRunner).to receive(:reconcile!)
    allow(EngineRunner).to receive(:snapshot).and_return(nil)

    visit new_session_path
    fill_in "Username", with: user.username
    fill_in "PIN", with: "1010"
    click_button "Sign in"
    visit practice_session_path(session)
    find("h1").click   # sound on
    expect(page).to have_button("🔊 Sound on")

    click_link "Plot it →", match: :first
    within("dialog[open]") do
      expect(page).to have_text("shot not scored")
      find("img[data-pinpoint-target='image']").click
      click_button "Score this hole"
      expect(page).to have_text("Scored 9.") # (-9, 3) mm: a 9
    end
    expect(page).to have_no_css("dialog[open]", wait: 5)   # closes itself
    expect(page).to have_button("🔊 Sound on")             # never left the page
    expect(capture.reload).to be_scored.and(be_pinpointed)
    expect(page).to have_no_link("Plot it →")
  end
end
