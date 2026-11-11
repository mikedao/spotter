require "rails_helper"

RSpec.describe "Engine events API" do
  # The web app creates the session (EngineRunner) before the engine reports into it.
  let!(:session) { create(:practice_session, engine_session_id: "20261111-153102-4f2a", status: "starting") }
  let(:sid) { session.engine_session_id }
  let(:auth) { { "Authorization" => "Bearer #{session.run_token}" } }
  let(:png) { Rack::Test::UploadedFile.new(StringIO.new("\x89PNG fake"), "image/png", original_filename: "after.png") }

  def post_event(type, data = {}, at: "2026-11-11T15:31:10Z", files: {}, headers: auth, session_id: sid)
    post "/api/events", params: { event: { type:, session_id:, at:, data: }.to_json, **files }, headers:
  end

  def shot_data(id, x, y, **extra)
    { engine_shot_id: id, trigger: "sound", sound_db: 61.0, x_mm: x, y_mm: y, r_mm: Math.hypot(x, y),
      decimal: 8.4, ring: 8, inner_ten: false, rule: "pellet", line_mm: 1.2,
      estimates: { centroid: [ x, y ], circle_fit: { x:, y:, ok: true, arc_deg: 210 },
                   closeup: { centre: [ x, y ], px_per_mm: 20, size_px: 480 } },
      region: { dia_mm: 9.4 }, geometry: { ring_rms_mm: 0.11 } }.merge(extra)
  end

  it "fills the session with cards and shots from the engine's events" do
    post_event("session_started", { target: "pistol", rule: "pellet" })
    expect(response).to have_http_status(:created)
    post_event("ready")
    post_event("shot", shot_data("044", -20.5, 2.8), files: { after_image: png })
    post_event("shot", shot_data("045", 11.1, -1.3, ring: 9, decimal: 9.6), at: "2026-11-11T15:31:30Z")
    post_event("card_off")
    post_event("new_card", at: "2026-11-11T15:33:00Z")
    post_event("shot", shot_data("046", 1.0, 1.0, line_call: true), at: "2026-11-11T15:33:20Z")

    session.reload
    expect(session.cards.map(&:number)).to eq [ 1, 2 ]
    expect(session.cards.first.shots.map(&:number)).to eq [ 1, 2 ]
    expect(session.cards.second.shots.first).to have_attributes(number: 1, line_call: true, engine_shot_id: "046")
    expect(session.cards.first.shots.first.after_image).to be_attached
    expect(session.status).to eq "shooting"
  end

  it "says Stopping live from Stop until the engine has ended, even if the final check finds a shot" do
    user = session.user
    post session_path, params: { email_address: user.email_address, password: "range-day-10" }
    session.update!(status: "shooting", engine_pid: 999_999)
    allow(EngineRunner).to receive(:alive?).and_return(true)
    allow(EngineRunner).to receive(:reconcile!)
    allow(Process).to receive(:kill)

    post stop_practice_session_path(session)
    expect(Process).to have_received(:kill).with("INT", 999_999)
    follow_redirect!
    expect(response.body).to include("Stopping – a last check")
    expect(response.body).not_to include("Stop session", "the engine does a last check")   # no flash that never goes

    post_event("shot", shot_data("053", 9.0, 10.5))   # found by the final check
    expect(session.reload.status).to eq "stopping"

    post_event("session_ended")
    expect(session.reload).to have_attributes(status: "ended", live?: false)
  end

  it "does not duplicate a shot the engine posts twice" do
    2.times { post_event("shot", shot_data("044", -20.5, 2.8)) }
    expect(Shot.count).to eq 1
  end

  it "keeps captures the engine could not score" do
    post_event("unscored", { reason: "no new hole on the card", trigger: "sound" }, files: { after_image: png })
    shot = Shot.last
    expect(shot).to have_attributes(status: "unscored", unscored_reason: "no new hole on the card")
    expect(shot.after_image).to be_attached
  end

  it "rejects an unknown event type" do
    post_event("explode")
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "needs the session's own run token" do
    post_event("ready", headers: {})
    expect(response).to have_http_status(:unauthorized)

    other = create(:practice_session)
    post_event("ready", headers: { "Authorization" => "Bearer #{other.run_token}" })
    expect(response).to have_http_status(:unauthorized)
    expect(session.reload.status).to eq "starting"
  end

  it "refuses a session the web app never started" do
    post_event("ready", session_id: "made-up-by-someone")
    expect(response).to have_http_status(:unauthorized)
    expect(PracticeSession.count).to eq 1
  end
end
