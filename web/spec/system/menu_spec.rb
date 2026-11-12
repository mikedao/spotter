require "rails_helper"

# The app's menu: no top bar, a drawer that slides out from the ☰ button.
RSpec.describe "Menu" do
  let(:user) { create(:user, name: "Mike") }

  it "slides out from the menu button, goes where you pick, and closes on Escape" do
    visit new_session_path
    fill_in "Username", with: user.username
    fill_in "PIN", with: "1010"
    click_button "Sign in"

    expect(page).to have_css("h1", text: "Practice")
    expect(page).not_to have_css("#drawer", visible: :visible)
    page.save_screenshot(Rails.root.join("tmp/screenshots/menu_closed.png")) if ENV["SCREENSHOTS"]

    find("button[aria-label='Menu']").click
    within("#drawer") { expect(page).to have_text("Mike") }
    page.save_screenshot(Rails.root.join("tmp/screenshots/menu_open.png")) if ENV["SCREENSHOTS"]

    find("body").send_keys(:escape)
    expect(page).not_to have_css("#drawer", visible: :visible)

    find("button[aria-label='Menu']").click
    within("#drawer") { click_on "Settings" }
    expect(page).to have_css("h1", text: "Settings")
    expect(page).not_to have_css("#drawer", visible: :visible)

    find("button[aria-label='Menu']").click
    within("#drawer") { click_on "Sign out" }
    expect(page).to have_button("Sign in")
  end
end
