require "rails_helper"

# Confirmations are the app's own modal (ConfirmDialogComponent), not the
# browser's confirm() box: Turbo asks it for every data-turbo-confirm.
RSpec.describe "Confirmation modal" do
  let(:user) { create(:user) }
  let!(:practice) { create(:practice_session, user:, status: "ended", ended_at: Time.zone.parse("2026-11-11 16:30")) }

  before do
    visit new_session_path
    fill_in "Username", with: user.username
    fill_in "PIN", with: "1010"
    click_button "Sign in"
    visit practice_sessions_path
  end

  def dialog = find("dialog#confirm_dialog")
  def delete_button = find("button[aria-label='Delete #{practice.title}']")

  it "asks in a modal, and Cancel keeps the session" do
    delete_button.click
    expect(dialog).to have_text("Delete #{practice.title}? Your calls and the pictures go too.")
    expect(dialog).to have_button("Delete")                                 # a delete: the red button
    expect(dialog).to have_no_button("Continue")
    expect(page.evaluate_script("document.activeElement.textContent.trim()")).to eq "Cancel"   # never Enter-to-delete
    page.save_screenshot(Rails.root.join("tmp/screenshots/confirm_dialog.png")) if ENV["SCREENSHOTS"]

    within(dialog) { click_button "Cancel" }
    expect(page).to have_no_css("dialog#confirm_dialog[open]")
    expect(PracticeSession.exists?(practice.id)).to be true
  end

  it "keeps the session on Esc" do
    delete_button.click
    expect(page).to have_css("dialog#confirm_dialog[open]")
    page.driver.browser.keyboard.type(:Escape)
    expect(page).to have_no_css("dialog#confirm_dialog[open]")
    expect(PracticeSession.exists?(practice.id)).to be true
  end

  it "deletes on the modal's Delete button" do
    delete_button.click
    within(dialog) { click_button "Delete" }
    expect(page).to have_no_css("button[aria-label='Delete #{practice.title}']")
    expect(PracticeSession.exists?(practice.id)).to be false
  end
end
