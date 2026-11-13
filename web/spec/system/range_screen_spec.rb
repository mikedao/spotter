require "rails_helper"

# The range screen's layout in a real browser, live (camera in the right column)
# and after the session (the shot list moves up beside the target).
RSpec.describe "Range screen layout" do
  let(:user) { create(:user) }

  def shoot_a_card(session)
    card = create(:card, practice_session: session)
    [ [ 8, 8.5, -14, 12 ], [ 7, 7.6, -6, 24 ], [ 9, 9.4, 4, 9 ], [ 10, 10.3, 1, -2 ], [ 8, 8.8, 15, -10 ] ].each do |ring, dec, x, y|
      create(:shot, card:, ring:, decimal_score: dec, x_mm: x, y_mm: y)
    end
    create(:shot, card:, ring: 7, decimal_score: 7.9, x_mm: -20, y_mm: 18, line_call: true)
    create(:shot, card:, ring: 9, decimal_score: 9.2, x_mm: 6, y_mm: 8)
  end

  def sign_in_and_visit(session)
    allow(EngineRunner).to receive(:reconcile!)
    visit new_session_path
    fill_in "Username", with: user.username
    fill_in "PIN", with: "1010"
    click_button "Sign in"
    visit practice_session_path(session)
  end

  it "fits the match clock, the latest shot and the whole camera on a laptop screen" do
    session = create(:practice_session, user:, course: "match", status: "shooting",
                                        course_state: { "phase" => "window", "label" => "Sighting", "stage" => "sighting",
                                                        "skippable" => true, "ends_at" => 14.minutes.from_now.iso8601 })
    shoot_a_card(session)
    allow(EngineRunner).to receive(:snapshot).and_return(nil)
    allow(EngineRunner).to receive(:understands_pause?).and_return(true)   # the widest header: Pause, Re-find, Stop
    sign_in_and_visit(session)
    page.driver.resize(1322, 729)

    expect(page).to have_button("Start match")
    expect(page).to have_button("⏸ Pause")
    bottom = page.evaluate_script("document.querySelector(\"[aria-label='Camera']\").getBoundingClientRect().bottom")
    expect(bottom).to be <= 729
    page.save_screenshot(Rails.root.join("tmp/screenshots/range_match_laptop.png")) if ENV["SCREENSHOTS"]
  end

  def right_column = find("#range_side")

  it "sums up the whole session once it is over: every shot, the result, every card" do
    session = create(:practice_session, user:, status: "ended", ended_at: Time.current)
    shoot_a_card(session)
    shoot_a_card(session)
    sign_in_and_visit(session)

    expect(page).to have_text("All 14 shots")
    within("#session_result") do
      expect(page).to have_text("Session result")
      expect(page).to have_text("116")   # whole rings over both cards
    end
    expect(right_column).to have_css("a[href*='/cards/']", count: 2)   # each card, to its own page
    expect(page).to have_no_css("#live_list")
    expect(page).to have_no_css("[aria-label='Camera']")
    page.save_screenshot(Rails.root.join("tmp/screenshots/range_ended.png")) if ENV["SCREENSHOTS"]
  end

  it "keeps the latest shot and the camera at the top while live" do
    session = create(:practice_session, user:, status: "shooting")
    shoot_a_card(session)
    allow(EngineRunner).to receive(:snapshot).and_return(nil)
    sign_in_and_visit(session)

    expect(right_column).to have_css("[aria-label='Camera']")
    within("ol[aria-label='Shots on this card']") do
      expect(page).to have_css("a.ring-amber-500", count: 1, text: "9")   # the latest, amber as on the target
      expect(page).to have_css("a.border-red-500", text: "7")             # flagged, red as on the target
    end
    expect(right_column).to have_css("#live_list")
    page.save_screenshot(Rails.root.join("tmp/screenshots/range_live.png")) if ENV["SCREENSHOTS"]

    # Scrolled down to the end of the shot list, the target is still in view beside it.
    page.execute_script("document.getElementById('live_list').scrollIntoView(false)")
    top = -> { page.evaluate_script("document.getElementById('live_target').getBoundingClientRect().top") }
    20.times { break if top.() >= 0; sleep 0.05 }   # let the scroll and the sticky layout settle
    expect(top.()).to be >= 0   # its top edge on screen, not scrolled away
    page.save_screenshot(Rails.root.join("tmp/screenshots/range_live_scrolled.png")) if ENV["SCREENSHOTS"]
  end
end
