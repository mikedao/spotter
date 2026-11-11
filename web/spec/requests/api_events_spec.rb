require "rails_helper"

RSpec.describe "Engine events API" do
  let(:sid) { "20261111-153102-4f2a" }
  let(:png) { Rack::Test::UploadedFile.new(StringIO.new("\x89PNG fake"), "image/png", original_filename: "after.png") }

  def post_event(type, data = {}, at: "2026-11-11T15:31:10Z", files: {}, headers: {})
    post "/api/events", params: { event: { type:, session_id: sid, at:, data: }.to_json, **files }, headers:
  end

  def shot_data(id, x, y, **extra)
    { engine_shot_id: id, trigger: "sound", sound_db: 61.0, x_mm: x, y_mm: y, r_mm: Math.hypot(x, y),
      decimal: 8.4, ring: 8, inner_ten: false, rule: "pellet", line_mm: 1.2,
      estimates: { centroid: [ x, y ], circle_fit: { x:, y:, ok: true, arc_deg: 210 },
                   closeup: { centre: [ x, y ], px_per_mm: 20, size_px: 480 } },
      region: { dia_mm: 9.4 }, geometry: { ring_rms_mm: 0.11 } }.merge(extra)
  end

  it "builds a session, cards and shots from the engine's events" do
    post_event("session_started", { target: "pistol", rule: "pellet" })
    expect(response).to have_http_status(:created)
    post_event("ready")
    post_event("shot", shot_data("044", -20.5, 2.8), files: { after_image: png })
    post_event("shot", shot_data("045", 11.1, -1.3, ring: 9, decimal: 9.6), at: "2026-11-11T15:31:30Z")
    post_event("card_off")
    post_event("new_card", at: "2026-11-11T15:33:00Z")
    post_event("shot", shot_data("046", 1.0, 1.0, line_call: true), at: "2026-11-11T15:33:20Z")

    session = PracticeSession.find_by!(engine_session_id: sid)
    expect(session.cards.map(&:number)).to eq [ 1, 2 ]
    expect(session.cards.first.shots.map(&:number)).to eq [ 1, 2 ]
    expect(session.cards.second.shots.first).to have_attributes(number: 1, line_call: true, engine_shot_id: "046")
    expect(session.cards.first.shots.first.after_image).to be_attached
    expect(session.status).to eq "shooting"
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

  context "with SPOTTER_TOKEN set" do
    before { Rails.configuration.x.engine_token = "s3cret" }
    after { Rails.configuration.x.engine_token = nil }

    it "requires the token" do
      post_event("ready")
      expect(response).to have_http_status(:unauthorized)
      post_event("ready", headers: { "Authorization" => "Bearer s3cret" })
      expect(response).to have_http_status(:created)
    end
  end

  it "refuses other machines when no token is set" do
    post "/api/events", params: { event: { type: "ready", session_id: sid }.to_json }, env: { "REMOTE_ADDR" => "192.168.1.50" }
    expect(response).to have_http_status(:forbidden)
  end
end
