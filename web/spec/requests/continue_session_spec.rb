require "rails_helper"

# Continue: a finished practice session from today picks up again - stop,
# improve something, carry on in one session.
RSpec.describe "Continuing a session" do
  let(:user) { create(:user) }
  let!(:practice) { create(:practice_session, user:, status: "ended", started_at: 2.hours.ago, ended_at: 1.hour.ago) }

  before { sign_in(user) }

  it "offers Continue on a finished practice session from today, and starts it again" do
    get practice_session_path(practice)
    expect(response.body).to include("Continue session", resume_practice_session_path(practice))

    allow(EngineRunner).to receive(:continue!)
    post resume_practice_session_path(practice)
    expect(EngineRunner).to have_received(:continue!).with(practice)
    expect(response).to redirect_to(practice_session_path(practice))
  end

  it "doesn't offer it for a match, or a session from another day" do
    practice.update!(course: "match")
    get practice_session_path(practice)
    expect(response.body).not_to include("Continue session")

    practice.update!(course: nil, started_at: 3.days.ago, ended_at: 3.days.ago + 1.hour)
    get practice_session_path(practice)
    expect(response.body).not_to include("Continue session")
  end

  it "says why when it can't (another session is running)" do
    create(:practice_session, engine_pid: Process.pid, ended_at: nil)
    post resume_practice_session_path(practice)
    follow_redirect!
    expect(response.body).to include("one session at a time")
  end

  it "leaves the break out of the report's duration" do
    practice.update!(started_at: 3.hours.ago, ended_at: 1.hour.ago, break_seconds: 3600)   # 2 h, 1 h of it a break
    get practice_session_report_path(practice)
    expect(response.body).to include("60 min")
  end

  it "keeps another user's session out of reach" do
    other = create(:practice_session, user: create(:user), status: "ended", started_at: 1.hour.ago, ended_at: 10.minutes.ago)
    post resume_practice_session_path(other)
    expect(response).to have_http_status(:not_found)
  end
end
