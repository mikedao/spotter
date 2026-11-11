require "rails_helper"

# The Start form's camera picker, in a real browser: preview pictures behind the
# login, the remembered choice, and the URL option.
RSpec.describe "Starting a session" do
  let(:user) { create(:user, name: "Mike", last_camera: "1") }

  before do
    FileUtils.mkdir_p(CameraProbe.dir)
    [ 0, 1 ].each { FileUtils.cp(Rails.root.join("public/icon.png"), CameraProbe.dir.join("cam_#{it}.jpg")) }
    CameraProbe.results_path.write({ cameras: [
      { index: 0, width: 1920, height: 1080, brightness: 110, name_hint: "MacBook Neo Camera", preview: "cam_0.jpg" },
      { index: 1, width: 1920, height: 1080, brightness: 95, name_hint: "Razer Kiyo", preview: "cam_1.jpg" }
    ] }.to_json)
  end

  after { FileUtils.rm_rf(CameraProbe.dir) }

  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email_address
    fill_in "Password", with: "range-day-10"
    click_button "Sign in"
  end

  it "shows each camera's picture and pre-selects the one used last" do
    sign_in_as(user)
    expect(page).to have_text("Razer Kiyo")
    expect(page).to have_css("img[src*='/cameras/0/preview']")
    expect(find("input[value='1']", visible: :all)).to be_checked
    page.save_screenshot(Rails.root.join("tmp/screenshots/start_session.png")) if ENV["SCREENSHOTS"]
  end
end
