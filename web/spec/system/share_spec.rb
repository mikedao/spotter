require "rails_helper"

# The share page in a real browser: the previews are the JPEGs that will be
# posted, and a colorway pill redraws them without losing the caption typed.
RSpec.describe "Sharing to CompetitiveShooter.org", if: system("which rsvg-convert > /dev/null 2>&1") do
  let(:user) { create(:user, cso_api_key: "csk_#{'d' * 32}") }

  it "previews the pictures and recolors them in place" do
    session = create(:practice_session, user:, status: "ended", ended_at: Time.current)
    card = create(:card, practice_session: session, number: 1)
    10.times { |i| create(:shot, card:, number: i + 1, ring: 10 - i % 3, x_mm: (i - 5) * 2.0, y_mm: 1.0) }

    visit new_session_path
    fill_in "Username", with: user.username
    fill_in "PIN", with: "1010"
    click_button "Sign in"
    visit new_share_path(session_ids: [ session.id ])

    widths = -> { page.evaluate_script("[...document.querySelectorAll('img[data-kind]')].map(i => i.complete ? i.naturalWidth : 0)") }
    page.execute_script("document.querySelectorAll('img[data-kind]').forEach(i => i.loading = 'eager')")
    Timeout.timeout(20) { sleep 0.2 until widths.().all?(SharePicture::W) }

    fill_in "body", with: "Keep me"
    find("label", text: "Range green").click
    expect(page).to have_css("img[data-kind=hero][src*='colors=forest']")
    expect(find_field("body").value).to eq("Keep me")
    page.save_screenshot("tmp/screenshots/share.png", full: true) if ENV["SCREENSHOTS"]
  end
end
