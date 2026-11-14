require "rails_helper"

# The Scoring model page: how the learned hole locator's training is going.
RSpec.describe "The scoring model page" do
  let(:user) { create(:user) }
  let(:engine) { Rails.root.join("tmp/scoring-model-test") }
  let(:ml) { engine.join("out/ml") }

  around do |example|
    FileUtils.rm_rf(engine)
    ml.join("model").mkpath
    old = ENV["SPOTTER_ENGINE_DIR"]
    ENV["SPOTTER_ENGINE_DIR"] = engine.to_s
    example.run
  ensure
    ENV["SPOTTER_ENGINE_DIR"] = old
    FileUtils.rm_rf(engine)
  end

  before { sign_in(user) }

  it "says how to start before there are any results" do
    get scoring_model_path
    expect(response.body).to include("No results yet", "bin/rails ml:update")
  end

  it "shows readiness, the live sessions, the disagreements with links, calibration and the trainings" do
    session = create(:practice_session, user:, status: "ended", ended_at: Time.current)
    shot = create(:shot, card: create(:card, practice_session: session))
    ml.join("eval-history.jsonl").write({
      per_session: [ { session_id: session.id, date: "2026-11-14", n: 60, agree: 58, tapped: 23, median_mm: 0.85, model_n: 60,
                       model_agree: 57, model_median_mm: 0.62, model_right: 1, rules_right: 2, neither: 0, flagged: 20,
                       flags_caught: 2, ring_changed: 2, model_flagged: 11, model_flags_caught: 3, model_wrong: 3,
                       model_versions: [ "20261113-1813" ] } ],
      head_to_head: { n: 60, same: 57, model_right: 1, rules_right: 2, neither: 0,
                      shots: [ { shot_id: shot.id, session_id: session.id, rules: 5, model: 6, called: 6, p_ring: 0.57, right: "model" } ] },
      calibration: [ { p_from: 0.99, p_to: 1.0, n: 46, right: 46, mean_p: 0.999 } ]
    }.to_json + "\n")
    ml.join("model/hole.json").write({ version: "20261113-2230", trained_on: 120, sessions: 2,
                                       cv: { by: "card", n: 120, rules_agree: 112, model_agree: 115, rules_ci95: [ 0.87, 0.97 ],
                                             model_ci95: [ 0.9, 0.98 ], rules_median_mm: 0.6, model_median_mm: 0.3 } }.to_json)
    ModelProgress.record!

    get scoring_model_path
    body = response.body
    expect(body).to include("Ready to score? Too early to tell", "1 of 3 sessions")
    expect(body).to include("58 → 57", "1 : 2")                              # tiles: live rings, who was right
    expect(body).to include(shot_path(shot), "57%")                          # the disagreement, linked
    expect(body).to include("46 <span", "(100.0%)")                           # calibration
    expect(body).to include("20261113-2230", "112/120", "115/120", "87-97%")   # the training, with its range
    expect(body).to include("<svg")
  end
end
