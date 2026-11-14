require "rails_helper"

# Deleting on the live range screen must not leave the page: leaving it stops the
# browser's microphone and the announcer (2026-11-13, 20 shots went unheard).
RSpec.describe "Deleting on the live range screen" do
  let(:user) { create(:user) }
  let(:session) { create(:practice_session, user:, status: "shooting") }
  let!(:card) { create(:card, practice_session: session, number: 1) }
  let!(:shots) { (1..3).map { create(:shot, card:, number: it, ring: 10 - it, x_mm: it.to_f, y_mm: 0.0) } }

  before do
    allow(EngineRunner).to receive(:reconcile!)
    allow(EngineRunner).to receive(:snapshot).and_return(nil)
    allow(EngineRunner).to receive(:forget!)
  end

  it "deletes a shot with a confirm and a toast, and the page stays" do
    visit new_session_path
    fill_in "Username", with: user.username
    fill_in "PIN", with: "1010"
    click_button "Sign in"
    visit practice_session_path(session)
    page.execute_script("window.stillHere = true")

    find("button[aria-label='Delete shot 2']").click
    within("dialog[open]") { click_button "Delete" }

    expect(page).to have_text("Deleted card 1, shot 2.")
    expect(page.evaluate_script("window.stillHere")).to be true   # no page load
    expect(page).to have_current_path(practice_session_path(session))
    expect(card.shots.order(:number).pluck(:number, :ring)).to eq([ [ 1, 9 ], [ 2, 7 ] ])
  end
end
