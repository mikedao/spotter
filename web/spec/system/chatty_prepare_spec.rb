require "rails_helper"

# Settings: chatty mode's remarks are built into some voices; in the others the
# shooter can prepare them ahead so no remark waits to be made.
RSpec.describe "Preparing chatty remarks" do
  let(:user) { create(:user) }

  before do
    allow(Voice).to receive(:available?).and_return(true)
    allow(Voice).to receive(:preparing?).and_return(false)
    allow(Voice).to receive(:chatty_built_in?) { |id, _| %w[af_bella af_nicole].include?(id) }
    allow(Voice).to receive(:chatty_readiness).and_return(Voice::ChattyReadiness.new(ready: 8, total: 1935))
    allow(Voice).to receive(:prewarm!)
    visit new_session_path
    fill_in "Username", with: user.username
    fill_in "PIN", with: "1010"
    click_button "Sign in"
  end

  it "offers to prepare them in the user's voice" do
    visit settings_path
    expect(page).to have_text("Chatty mode in Heart")
    expect(page).to have_text("built into Bella and Nicole only")
    expect(page).to have_text("💬 built in", count: 2)
    page.scroll_to(find("#chatty_readiness"), align: :center)
    page.save_screenshot(Rails.root.join("tmp/screenshots/chatty_prepare.png")) if ENV["SCREENSHOTS"]

    click_button "Prepare chatty remarks now"
    expect(page).to have_css("[role='status']", text: "Preparing Heart's chatty remarks")
    expect(Voice).to have_received(:prewarm!).with("af_heart", extra: Commentary.pieces(user))
  end
end
