require "rails_helper"

# The finished session page's "Scoring model" card.
RSpec.describe "Updating the scoring model from a session" do
  let(:user) { create(:user) }
  let(:session) { create(:practice_session, user:, status: "ended", ended_at: Time.current, started_at: 1.hour.ago) }
  let(:card) { create(:card, practice_session: session, number: 1) }

  before { sign_in(user) }

  def shot(called:)
    create(:shot, card:, ring: 9, decimal_score: 9.3, x_mm: 5.0, y_mm: 1.0,
                  call_ring: (9 if called), called_at: (Time.current if called))
  end

  it "asks for the rest of the review first, then offers the update" do
    shot(called: true)
    uncalled = shot(called: false)
    get practice_session_path(session)
    expect(response.body).to include("1 shot still to review")
    expect(response.body).to include(shot_path(uncalled))
    expect(response.body).not_to include("Update the scoring model")

    uncalled.update!(call_ring: 9, called_at: Time.current)
    get practice_session_path(session)
    expect(response.body).to include("Update the scoring model")
  end

  it "starts it, and shows the results when done" do
    shot(called: true)
    allow(ModelUpdate).to receive(:start!).with(session)
    post update_model_practice_session_path(session)
    expect(response).to redirect_to(practice_session_path(session, anchor: "model_update"))

    session.update_column(:model_update, {
      "status" => "done", "result" => {
        "session" => { "n" => 60, "agree" => 54, "model_n" => 60, "model_agree" => 58 },
        "trained" => { "trained_on" => 120, "cv" => { "by" => "session", "n" => 120, "rules_agree" => 108, "model_agree" => 115 } }
      }
    })
    get practice_session_path(session)
    expect(response.body).to include("engine 54 of 60").and include("model 58 of 60")
    expect(response.body).to include("Retrained on 120 called shots")
    expect(response.body).to include("Run again")
  end

  it "isn't shown while the session is live" do
    live = create(:practice_session, user:)
    allow(EngineRunner).to receive(:reconcile!)   # no real engine behind it
    get practice_session_path(live)
    expect(response.body).not_to include("Scoring model")
  end

  it "is another user's session: not found" do
    other = create(:practice_session, user: create(:user), status: "ended", ended_at: Time.current)
    post update_model_practice_session_path(other)
    expect(response).to have_http_status(:not_found)
  end
end
