require "rails_helper"

# The scoring model's progress, one row per trained model.
RSpec.describe ModelProgress do
  let(:engine) { Rails.root.join("tmp/model-progress-test") }
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

  def train(version, cv_model:)
    ml.join("model/hole.json").write({ version:, trained_on: 120, sessions: 2,
                                       cv: { by: "card", n: 120, rules_agree: 110, model_agree: cv_model,
                                             rules_median_mm: 0.6, model_median_mm: 0.3, model_flags: { flagged: 9 }, flags: { flagged: 40 } } }.to_json)
  end

  def evaluated(per_session)
    ml.join("eval-history.jsonl").open("a") { it.puts({ per_session:, flags: { flagged: 40 } }.to_json) }
  end

  it "records each trained model once, with the latest session live and the held-out check, and shows the history" do
    evaluated([ { session_id: 8, date: "2026-11-13", n: 60, agree: 54, model_n: 0, model_agree: 0 },
                { session_id: 10, date: "2026-11-14", n: 60, agree: 58, model_n: 60, model_agree: 57 } ])
    train("20261113-2230", cv_model: 115)

    row = described_class.record!
    expect(row["latest_session"]).to include("session_id" => 10, "rules_agree" => 58, "model_agree" => 57, "model_n" => 60)
    expect(row["live"]).to include("sessions" => 1, "n" => 60, "rules_agree" => 58, "model_agree" => 57)
    expect(row["held_out"]).to include("rules_agree" => 110, "model_agree" => 115, "model_flagged" => 9, "rules_flagged" => 40)
    expect(described_class.record!).to be_nil   # once per model

    train("20261115-2100", cv_model: 117)
    described_class.record!
    table = described_class.table
    expect(table.lines.grep(/20261113-2230|20261115-2100/).size).to eq(2)
    expect(table).to include("58 -> 57 of 60", "110 -> 115 of 120", "0.60 -> 0.30", "9/40", "TOO EARLY TO TELL")
  end

  it "judges readiness on live sessions only, and only after three of them" do
    live = ->(id, rules, model, mr, rr) { { session_id: id, date: "2026-11-#{10 + id}", n: 60, agree: rules, model_n: 60, model_agree: model, model_right: mr, rules_right: rr } }
    evaluated([ live.(1, 55, 57, 3, 1), live.(2, 56, 58, 2, 0) ])
    expect(described_class.readiness.state).to eq(:early)

    evaluated([ live.(1, 55, 57, 3, 1), live.(2, 56, 58, 2, 0), live.(3, 57, 58, 2, 1) ])
    r = described_class.readiness
    expect(r.state).to eq(:ahead)
    expect(r.detail).to include("rings 168 (engine) vs 173 (model) of 180", "model right 7, engine right 2")

    evaluated([ live.(1, 58, 57, 1, 2), live.(2, 58, 57, 1, 2), live.(3, 58, 57, 1, 2) ])
    expect(described_class.readiness.state).to eq(:behind)
  end

  it "says so before any model is recorded" do
    expect(described_class.table).to include("No trained model recorded yet")
  end
end
