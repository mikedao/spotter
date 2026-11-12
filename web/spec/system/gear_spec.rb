require "rails_helper"

# The wizard's Gun / Pellets pickers in a real browser: changing the gun picks
# its pellets, "New lot of these" copies them so only the lot is typed.
RSpec.describe "Choosing a gun and pellets" do
  let(:user) { create(:user, last_camera: "1", last_mic: "Razer Kiyo") }

  def sign_in_as(user)
    visit new_session_path
    fill_in "Username", with: user.username
    fill_in "PIN", with: "1010"
    click_button "Sign in"
  end

  it "picks the pellets last used with the chosen gun, and starts a new lot" do
    lp10, morini = create(:gun, user:, name: "LP10"), create(:gun, user:, name: "Morini")
    r10, finale = create(:pellet, user:, lot: "1234"), create(:pellet, user:, name: "H&N Finale Match", head_mm: 4.5, lot: "9")
    create(:practice_session, user:, gun: lp10, pellet: r10, started_at: 2.days.ago)
    create(:practice_session, user:, gun: morini, pellet: finale, started_at: 1.day.ago)

    sign_in_as(user)
    visit setup_start_path
    expect(page).to have_select("Gun", selected: "Morini")
    expect(page).to have_select("Pellets", selected: finale.label)
    expect(page).to have_no_field("Lot")

    select "LP10", from: "Gun"
    expect(page).to have_select("Pellets", selected: r10.label)

    click_button "New lot of these"
    expect(page).to have_select("Pellets", selected: "New pellets…")
    expect(page).to have_field("Brand and name", with: "RWS R10 Match")
    expect(page).to have_field("Head (mm)", with: "4.49")
    fill_in "Lot", with: "5678"
    page.save_screenshot(Rails.root.join("tmp/screenshots/gear_start.png")) if ENV["SCREENSHOTS"]

    allow(EngineRunner).to receive(:start!) { |**args| create(:practice_session, user:, started_at: Time.current, **args[:gear]) }
    click_button "Start session"
    expect(page).to have_text("Gun and pellets")
    expect(user.practice_sessions.newest_first.first.pellet.label).to eq("RWS R10 Match · 4.49 mm · 7.0 gr · lot 5678")
  end
end
