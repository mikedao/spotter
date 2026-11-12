require "rails_helper"

# The session report: a printable page (Save as PDF), light, no app menu.
RSpec.describe "Session report" do
  let(:user) { create(:user, name: "Mike") }
  let(:session) do
    create(:practice_session, user:, status: "ended", started_at: 2.hours.ago, ended_at: 1.hour.ago,
                              gun: create(:gun, user:, name: "LP10"), problems: "Pulled low left", learned: "Breathe out first")
  end

  before do
    sign_in(user)
    card = create(:card, practice_session: session, number: 1)
    create(:shot, card:, number: 1, ring: 8, decimal_score: 8.5, x_mm: 20, y_mm: 0, stage: "sighter")
    [ 10, 9, 9, 10, 8, 9, 10, 9, 9, 9 ].each_with_index { |r, i| create(:shot, card:, number: i + 2, ring: r, decimal_score: r + 0.4, x_mm: i - 4.0, y_mm: 2.0) }
    create(:shot, card:, number: 12, status: "unscored", ring: nil, decimal_score: nil, x_mm: nil, y_mm: nil, unscored_reason: "view moving")
    session.exercises << user.exercises.create!(name: "Trigger control")
  end

  it "has the session's numbers, each card with its shots, and the notes" do
    get practice_session_report_path(session)
    body = response.body
    expect(body).to include("Save as PDF", "Mike", "LP10", "Trigger control", "60 min")
    expect(body).to include("Per 60 shots", "552", "10-shot series:", "92")   # 92 whole rings over 10 shots
    expect(body).to include("Card 1", "<svg", "sighter", "not scored - view moving")
    expect(body).to include("Pulled low left", "Breathe out first")
    expect(body).not_to include('aria-label="Menu"')   # the report layout, no app chrome
  end

  it "is linked from the session page and is the user's own only" do
    get practice_session_path(session)
    expect(response.body).to include(practice_session_report_path(session))
    get practice_session_report_path(create(:practice_session))
    expect(response).to have_http_status(:not_found)
  end
end
