require "rails_helper"

# The range screen in a match, in a real browser: the range officer's clock
# counts down, and the panel shows the match total, sighters and series.
RSpec.describe "Range screen in a match" do
  let(:user) { create(:user, name: "Mike") }
  let(:session) do
    create(:practice_session, user:, course: "match", status: "shooting",
                              course_state: { "phase" => "window", "label" => "Match", "stage" => "match",
                                              "ends_at" => 9.minutes.from_now.iso8601 })
  end

  it "counts down and shows the match score" do
    card = create(:card, practice_session: session)
    create(:shot, card:, stage: "sighter", ring: 8, decimal_score: 8.3, x_mm: -9, y_mm: 6)
    [ [ 9, 9.5, 4, -2 ], [ 10, 10.2, 1, 1 ], [ 9, 9.1, -5, 3 ] ].each_with_index do |(ring, dec, x, y), i|
      create(:shot, card:, stage: "match", match_number: i + 1, series: 1, ring:, decimal_score: dec, x_mm: x, y_mm: y)
    end
    allow(EngineRunner).to receive(:reconcile!)

    visit new_session_path
    fill_in "Username", with: user.username
    fill_in "PIN", with: "1010"
    click_button "Sign in"
    visit practice_session_path(session)

    expect(page).to have_css("[data-controller='countdown']", text: /\A8:5\d\z/)   # ticking, amber under 10 minutes
    expect(page).to have_css("[data-controller='countdown'].text-amber-600")
    within("#live_course") do
      expect(page).to have_text("28")      # whole rings: 9 + 10 + 9; the sighter adds nothing
      expect(page).to have_text("3 / 60")
      expect(page).to have_text("S1 28")
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/match.png")) if ENV["SCREENSHOTS"]
  end
end
