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
    post session_path, params: { username: user.username, pin: "1010" }
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

  it "says the practice summary before the range screen reloads into the finished session" do
    post_event("shot", shot_data("044", 1.0, 1.0, ring: 9, decimal: 9.6))
    order = []
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to) { |*, target:, **| order << target }
    allow(Turbo::StreamsChannel).to receive(:broadcast_refresh_to) { order << "refresh" }
    post_event("session_ended")
    expect(order).to eq [ "announcements", "refresh" ]
  end

  it "takes a shot at once and its pictures when they follow (the engine's picture lane)" do
    post_event("shot", shot_data("050", 4.0, -3.0, detect_s: 1.37))
    shot = session.shots.find_by!(engine_shot_id: "050")
    expect(shot.detect_seconds).to eq 1.37                       # sound to score
    expect(shot.after_image).not_to be_attached

    expect(LiveBroadcast).not_to receive(:new)                   # the range screen doesn't show them
    expect(Commentary).not_to receive(:after_event)              # and no second chatty remark
    post_event("shot_images", { engine_shot_id: "050" }, files: { after_image: png })
    expect(response).to have_http_status(:created)
    expect(shot.reload.after_image).to be_attached
  end

  it "refuses pictures for a shot it doesn't have" do
    post_event("shot_images", { engine_shot_id: "999" }, files: { after_image: png })
    expect(response).to have_http_status(:unprocessable_entity)
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

  it "takes the engine's later find of a just-plotted shot as the same shot, not a second one" do
    card = create(:card, practice_session: session, number: 1)
    plotted = create(:shot, card:, number: 1, engine_shot_id: nil, x_mm: -9.0, y_mm: 3.0, ring: 9, decimal_score: 9.3,
                            pinpointed_at: 1.minute.ago, fired_at: 2.minutes.ago)
    post_event("shot", shot_data("080", -8.2, 3.5, trigger: "camera", ring: 9, decimal: 9.4))   # its hole, found by the camera
    expect(card.shots.count).to eq 1
    expect(plotted.reload).to have_attributes(engine_shot_id: "080", x_mm: -8.2, pinpointed_at: nil, number: 1)
  end

  it "keeps a new shot that lands next to a plotted one: it came with a sound" do
    card = create(:card, practice_session: session, number: 1)
    create(:shot, card:, number: 1, engine_shot_id: nil, x_mm: -9.0, y_mm: 3.0, pinpointed_at: 1.minute.ago, fired_at: 2.minutes.ago)
    post_event("shot", shot_data("081", -8.0, 3.0, trigger: "sound"))
    expect(card.shots.count).to eq 2
  end

  it "hands an announcement to the range screen without redrawing it" do
    allow(Announcement).to receive(:new).and_call_original
    allow(LiveBroadcast).to receive(:new).and_call_original
    post_event("announce", { kind: "ok", plain_kind: "ok", gaps: { sentence: 0.55, comma: 0.25 },
                             sentences: [ { pieces: [ "ready" ], diagnostic: false } ] })
    expect(response).to have_http_status(:created)
    expect(Announcement).to have_received(:new)
    expect(LiveBroadcast).not_to have_received(:new)
  end

  context "in a match" do
    before { session.update!(course: "match", status: "ready") }

    it "shows the range officer's clock, sighters, out-of-time zeros and the match total" do
      post_event("course", { phase: "window", label: "Sighting", stage: "sighting", skippable: true,
                             ends_at: "2026-11-11T15:46:00Z" })
      expect(session.reload.course_state).to include("label" => "Sighting", "skippable" => true)

      post_event("shot", shot_data("060", 1.0, -4.0, ring: 9, decimal: 9.4, course: { stage: "sighter", label: "Sighting" }))
      post_event("shot", shot_data("061", 0.5, 0.5, ring: 10, decimal: 10.6,
                                   course: { stage: "match", label: "Match", series: 1, number: 1 }))
      post_event("shot", shot_data("062", 3.0, 9.0, ring: 9, decimal: 9.2,
                                   course: { stage: "match", label: "Match", series: 1, number: 2, penalty: "out of time" }))

      expect(session.shots.order(:id).pluck(:stage, :match_number, :penalty))
        .to eq [ [ "sighter", nil, nil ], [ "match", 1, nil ], [ "match", 2, "out of time" ] ]

      sign_in(session.user)
      allow(EngineRunner).to receive(:reconcile!)   # no real engine behind it
      get practice_session_path(session)
      expect(response.body).to include("Match", "Start match", "data-countdown-ends-at-value",
                                       "1 shot out of time, scored zero", "out of time - scores 0")
      expect(response.body).to match(%r{Total</dt>\s*<dd[^>]*>10</dd>})   # whole rings; the sighter and the late shot add nothing
    end

    it "numbers a new competition shot from its own count, so a deleted shot leaves no gap" do
      (1..3).each do |n|
        post_event("shot", shot_data("07#{n}", n.to_f, 1.0, ring: 9, decimal: 9.3,
                                     course: { stage: "match", label: "Match", series: 1, number: n }))
      end
      session.shots.find_by(match_number: 2).remove!
      post_event("shot", shot_data("074", 4.0, 1.0, ring: 10, decimal: 10.2,
                                   course: { stage: "match", label: "Match", series: 1, number: 4 }))   # the engine still counts 4
      expect(session.shots.order(:match_number).pluck(:engine_shot_id, :match_number)).to eq [ [ "071", 1 ], [ "073", 2 ], [ "074", 3 ] ]
    end

    it "asks the engine to re-find the target, without a page load" do
      sign_in(session.user)
      allow(EngineRunner).to receive(:refind!).and_return(true)
      post refind_practice_session_path(session)
      expect(response).to have_http_status(:no_content)
      expect(EngineRunner).to have_received(:refind!).with(session)
    end

    it "never signals an engine that doesn't understand re-find (it would die)" do
      log = Rails.root.join("tmp", "engine-refind-spec.log")
      log.write("  baseline taken. Ready - fire when you like.\n")   # an older engine: no "re-find target" line
      session.update!(engine_pid: Process.pid, engine_log: log.to_s)
      allow(Process).to receive(:kill).and_call_original
      expect(EngineRunner.refind!(session)).to be(false)
      expect(Process).not_to have_received(:kill).with("USR2", anything)
      log.write("  re-find target: SIGUSR2\n")
      allow(Process).to receive(:kill).with("USR2", Process.pid)
      expect(EngineRunner.refind!(session)).to be(true)
    ensure
      FileUtils.rm_f(log)
    end

    it "pauses scoring to change cards, and resumes - without a page load" do
      log = Rails.root.join("tmp", "engine-pause-spec.log")
      log.write("  pause scoring: SIGTSTP / SIGCONT\n")
      session.update!(engine_pid: Process.pid, engine_log: log.to_s, status: "ready")
      allow(Process).to receive(:kill).and_call_original
      allow(Process).to receive(:kill).with("TSTP", Process.pid)
      allow(Process).to receive(:kill).with("CONT", Process.pid)
      sign_in(session.user)

      get practice_session_path(session)
      expect(response.body).to include(pause_scoring_practice_session_path(session), refind_practice_session_path(session))
      post pause_scoring_practice_session_path(session)
      expect(response).to have_http_status(:no_content)
      expect(Process).to have_received(:kill).with("TSTP", Process.pid)
      expect(session.reload.status).to eq "paused"
      post_event("paused")                    # the engine confirms: still paused
      expect(session.reload.status).to eq "paused"
      allow(EngineRunner).to receive(:reconcile!)
      get practice_session_path(session)
      expect(response.body).to include("Scoring paused", resume_scoring_practice_session_path(session))
      expect(response.body).not_to include(pause_scoring_practice_session_path(session), refind_practice_session_path(session))

      post resume_scoring_practice_session_path(session)
      expect(response).to have_http_status(:no_content)
      expect(Process).to have_received(:kill).with("CONT", Process.pid)
      expect(session.reload.status).to eq "resuming"
      post_event("new_card")                  # resumed on a fresh card
      expect(session.reload).to have_attributes(status: "new_card")
    ensure
      FileUtils.rm_f(log)
    end

    it "never pauses an engine that doesn't understand it (SIGTSTP would suspend it)" do
      log = Rails.root.join("tmp", "engine-pause-old-spec.log")
      log.write("  re-find target: SIGUSR2\n")
      session.update!(engine_pid: Process.pid, engine_log: log.to_s, status: "ready")
      allow(Process).to receive(:kill).and_call_original
      expect(EngineRunner.pause!(session)).to be(false)
      expect(Process).not_to have_received(:kill).with("TSTP", anything)
      expect(session.reload.status).to eq "ready"
      expect(EngineRunner.resume_scoring!(session)).to be(false)   # not paused: nothing to resume
      sign_in(session.user)
      allow(EngineRunner).to receive(:reconcile!)
      get practice_session_path(session)
      expect(response.body).to include(refind_practice_session_path(session))
      expect(response.body).not_to include(pause_scoring_practice_session_path(session))   # no button for it either
    ensure
      FileUtils.rm_f(log)
    end

    it "ends sighting time early when asked" do
      sign_in(session.user)
      allow(EngineRunner).to receive(:start_match!)
      post start_match_practice_session_path(session)
      expect(EngineRunner).to have_received(:start_match!).with(session)
    end
  end
end
