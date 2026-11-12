require "rails_helper"

RSpec.describe "Shotmetrix QR code" do
  let(:user) { create(:user) }
  let(:session) { create(:practice_session, user:, status: "ended", ended_at: Time.current, started_at: 1.hour.ago) }

  before { sign_in(user) }

  it "shows the session as a version 24 QR code, linked from the session page" do
    create(:shot, card: create(:card, practice_session: session), ring: 10, decimal_score: 10.4, x_mm: 2.0, y_mm: 1.0)
    get practice_session_path(session)
    expect(response.body).to include(practice_session_shotmetrix_path(session))

    get practice_session_shotmetrix_path(session)
    expect(response.body).to include("Send to Shotmetrix", "<svg", "1 shot, whole rings")
    expect(response.body).to include('data-qr-version="24"')
  end

  it "says when there's nothing to send" do
    get practice_session_shotmetrix_path(session)
    expect(response.body).to include("nothing to send")
  end

  it "is the user's own sessions only" do
    get practice_session_shotmetrix_path(create(:practice_session))
    expect(response).to have_http_status(:not_found)
  end
end
