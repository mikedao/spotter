require "rails_helper"

# The wizard's Start step for a session started from a plan block: the block is
# its own choice under "What are you shooting?", and the choice fills in shots per
# card and groups.
RSpec.describe "Starting a session from the plan" do
  let(:user) { create(:user, last_camera: "0", last_mic: "none") }

  before do
    user.create_plan_enrollment!(started_on: Time.zone.today)
    allow(CameraProbe).to receive(:run!)
    visit new_session_path
    fill_in "Username", with: user.username
    fill_in "PIN", with: "1010"
    click_button "Sign in"
  end

  def per_card = find_field("Shots per card").value
  def groups = find("input[name='practice_session[group_of]']:checked").value

  it "picks the plan block, with its card and groups, and swaps them as the choice changes" do
    visit plan_workout_path(12, 2)
    click_button "Start the session: Air pistol (FWB 65)"
    visit setup_start_path
    expect(page).to have_css("[data-plan-option]", text: /from your training plan/i)
    expect(page).to have_text("Air pistol (FWB 65)")
    expect(find("input[value='plan']")).to be_checked
    expect(per_card).to eq("10")
    expect(groups).to eq("0")
    page.save_screenshot(Rails.root.join("tmp/screenshots/plan_start.png")) if ENV["SCREENSHOTS"]

    fill_in "Shots per card", with: "7"
    find("label", text: "No clock; every shot counts").click
    expect(per_card).to eq("10")

    fill_in "Shots per card", with: "7"
    find("[data-plan-option]").click
    expect(per_card).to eq("10")
  end

  it "fills in 5-shot groups for a block that shoots them" do
    visit plan_workout_path(1, 3)
    click_button "Start the session: Trigger groups"
    visit setup_start_path
    expect(per_card).to eq("10")
    expect(groups).to eq("5")
    find("label", text: "No clock; every shot counts").click
    expect(groups).to eq("0")
    find("[data-plan-option]").click
    expect(groups).to eq("5")
  end
end
