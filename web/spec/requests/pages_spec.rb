require "rails_helper"

RSpec.describe "Pages" do
  let(:user) { create(:user) }
  let(:session) { create(:practice_session, user:) }
  let(:card) { create(:card, practice_session: session) }
  let!(:shot) do
    create(:shot, card:, x_mm: -20.5, y_mm: 2.8, ring: 8, decimal_score: 8.4, line_call: true,
                  estimates: { "closeup" => { "centre" => [ -20.5, 2.8 ], "px_per_mm" => 20, "size_px" => 480 } })
  end

  context "signed in" do
    before do
      sign_in(user)
      allow(EngineRunner).to receive(:reconcile!)   # the factory's session is live; no engine to find dead
    end

    it "lists the user's sessions with a way to start one" do
      get root_path
      expect(response.body).to include("10m Air Pistol", "New session")
    end

    it "shows the range screen with the target, latest shot and stats" do
      get practice_session_path(session)
      expect(response.body).to include("<svg", "Latest shot", "8.4", "Check by eye: line call")
    end

    it "lines up the card's shots under the latest as whole rings, your call winning" do
      create(:shot, card:, ring: 10, decimal_score: 10.4)
      create(:shot, card:, ring: 9, decimal_score: 9.8, call_ring: 8)
      create(:shot, card:, ring: 9, decimal_score: 9.1, penalty: "out of time")
      get practice_session_path(session)
      row = Nokogiri::HTML(response.body).at_css("ol[aria-label='Shots on this card']")
      expect(row.css("a").map(&:text)).to eq(%w[ 8 10 8 0 ])
    end

    it "points an arrow where the latest shot went" do
      get practice_session_path(session)   # x -20.5, y 2.8: left, a little high
      expect(response.body).to include("rotate(-172deg)", "left")
    end

    it "shows an empty card before the first shot" do
      fresh = create(:practice_session, user:, status: "ready")
      get practice_session_path(fresh)
      expect(response.body).to include("Card 1", "<svg", "no shots on this card yet")
      expect(response.body).not_to include("Waiting for the first shot")
    end

    it "shows the live camera and Stop only while the session runs" do
      live = create(:practice_session, user:, status: "ready")
      allow(EngineRunner).to receive(:reconcile!)   # no real engine behind it
      get practice_session_path(live)
      expect(response.body).to include("Camera", camera_practice_session_path(live), "■ Stop")

      live.update!(status: "ended", ended_at: Time.current)
      get practice_session_path(live)
      expect(response.body).not_to include(camera_practice_session_path(live), "■ Stop")
    end

    it "relays the engine's live picture, and says 204 when there is none" do
      live = create(:practice_session, user:, status: "ready", stream_port: 45_999)
      allow(EngineRunner).to receive(:snapshot).and_return("\xFF\xD8jpeg".b)
      get camera_practice_session_path(live)
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq "image/jpeg"

      allow(EngineRunner).to receive(:snapshot).and_call_original
      get camera_practice_session_path(live)   # nothing listening on that port
      expect(response).to have_http_status(:no_content)

      live.update!(status: "ended", ended_at: Time.current)
      get camera_practice_session_path(live)
      expect(response).to have_http_status(:gone)
    end

    it "deletes a finished session with its cards, shots, pictures and engine log" do
      session.update!(status: "ended", ended_at: Time.current,
                      engine_log: Rails.root.join("log/engine/spec-delete.log").to_s)
      FileUtils.mkdir_p(Rails.root.join("log/engine"))
      File.write(session.engine_log, "engine output")
      shot.after_image.attach(io: StringIO.new("png"), filename: "after.png", content_type: "image/png")
      blob = shot.after_image.blob

      get practice_sessions_path
      expect(response.body).to include("Delete", "This can&#39;t be undone")

      expect { delete practice_session_path(session) }
        .to change(PracticeSession, :count).by(-1).and change(Card, :count).by(-1).and change(Shot, :count).by(-1)
      expect(response).to redirect_to(practice_sessions_path)
      expect(ActiveStorage::Blob.exists?(blob.id)).to be false
      expect(File).not_to exist(session.engine_log)
    end

    it "refuses to delete a running session" do
      allow(EngineRunner).to receive(:reconcile!)   # its engine is running
      expect { delete practice_session_path(session) }.not_to change(PracticeSession, :count)
      expect(Shot.exists?(shot.id)).to be true
      follow_redirect!
      expect(response.body).to include("Stop the session before deleting it")
    end

    it "shows a shot for review" do
      get shot_path(shot)
      expect(response.body).to include("Your call", "Flagged: line call")
    end

    it "records the shooter's call beside the proposal" do
      patch shot_path(shot), params: { shot: { ring: "9", x_mm: "-18.4", y_mm: "2.1", note: "touches the 9" } }
      shot.reload
      expect(shot).to have_attributes(call_ring: 9, call_x_mm: -18.4, call_note: "touches the 9", ring: 8)
      expect(shot.called_at).to be_present
    end
  end

  context "another user" do
    before { sign_in(create(:user)) }

    it "cannot see or change someone else's sessions and shots" do
      get root_path
      expect(response.body).not_to include(practice_session_path(session))

      get practice_session_path(session)
      expect(response).to have_http_status(:not_found)
      get camera_practice_session_path(session)
      expect(response).to have_http_status(:not_found)
      get shot_path(shot)
      expect(response).to have_http_status(:not_found)
      patch shot_path(shot), params: { shot: { ring: "10" } }
      expect(response).to have_http_status(:not_found)
      delete practice_session_path(session)
      expect(response).to have_http_status(:not_found)
      expect(PracticeSession.exists?(session.id)).to be true
      expect(shot.reload.call_ring).to be_nil
    end
  end

  it "sends a signed-out visitor to sign in" do
    get practice_session_path(session)
    expect(response).to redirect_to(new_session_path)
  end
end
