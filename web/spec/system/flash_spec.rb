require "rails_helper"

# Flash messages are toasts: over the page, a notice fades away, an alert stays.
RSpec.describe "Flash messages" do
  let(:user) { create(:user) }

  before do
    visit new_session_path
    fill_in "Username", with: user.username
    fill_in "PIN", with: "1010"
    click_button "Sign in"
  end

  it "fades a notice away after a few seconds, without moving the page" do
    visit settings_path
    heading_top = page.evaluate_script("document.querySelector('h1').getBoundingClientRect().top")
    click_button "Save", match: :first
    expect(page).to have_css("[role='status']", text: "Saved what the announcer says")
    page.save_screenshot(Rails.root.join("tmp/screenshots/flash_notice.png")) if ENV["SCREENSHOTS"]
    expect(page.evaluate_script("document.querySelector('h1').getBoundingClientRect().top")).to eq(heading_top)   # floats over
    expect(page).to have_no_css("[role='status']", wait: 8)
  end

  it "keeps an alert until it is closed" do
    Capybara.reset_session!
    visit new_session_path
    fill_in "Username", with: user.username
    fill_in "PIN", with: "9999"   # wrong
    click_button "Sign in"
    expect(page).to have_css("[role='alert']", text: "Try another username or PIN")
    sleep 6
    expect(page).to have_css("[role='alert']")   # still there
    find("[role='alert'] button[aria-label='Close']").click
    expect(page).to have_no_css("[role='alert']")
  end
end
