require "rails_helper"

# The after-session routine behind "Update the scoring model", with stand-in
# scripts for the engine's mleval.py and the training run (the real ones need the
# engine's Python and ~15 minutes of GPU).
RSpec.describe ModelUpdate do
  let(:root) { Rails.root.join("tmp/model-update-test") }
  let(:engine) { root.join("engine") }
  let(:user) { create(:user) }
  let(:session) { create(:practice_session, user:, status: "ended", ended_at: Time.current, started_at: 1.hour.ago) }
  let(:card) { create(:card, practice_session: session, number: 1) }

  def script(name, body)
    root.join(name).tap { it.write("#!/bin/sh\n#{body}\n"); it.chmod(0o755) }
  end

  # mleval.py --save --json: the summary, this session's line in it
  def compare_script(session_id)
    summary = { shots: 2, sessions: 1, ring: { rules: { agree: 1, n: 2 }, model: { agree: 2, n: 2 } },
                per_session: [ { session_id:, n: 2, agree: 1, model_n: 2, model_agree: 2 } ] }
    script("python", "cat <<'JSON'\n#{JSON.generate(summary)}\nJSON")
  end

  # ml/train.py: writes the exported model's metadata where the engine keeps it
  def train_script(fail: false)
    meta = { version: "20261114-0900", trained_on: 2, sessions: 1, cv: { by: "card", n: 2, rules_agree: 1, model_agree: 2 } }
    script("ml-python", fail ? "echo 'RuntimeError: out of memory' >&2; exit 1" :
                               "mkdir -p out/ml/model && echo '#{JSON.generate(meta)}' > out/ml/model/hole.json")
  end

  around do |example|
    FileUtils.rm_rf(root)
    engine.mkpath
    env = { "SPOTTER_ENGINE_DIR" => engine.to_s, "SPOTTER_PYTHON" => nil, "SPOTTER_ML_PYTHON" => nil }
    old = env.keys.index_with { ENV[it] }
    env.each { |k, v| ENV[k] = v }
    example.run
  ensure
    old.each { |k, v| ENV[k] = v }
    FileUtils.rm_rf(root)
  end

  def shot(called: true)
    create(:shot, card:, ring: 9, decimal_score: 9.3, x_mm: 5.0, y_mm: 1.0,
                  call_ring: (9 if called), called_at: (Time.current if called))
  end

  def run!(session)
    ENV["SPOTTER_PYTHON"] = compare_script(session.id).to_s
    ModelUpdate.start!(session).join
    session.reload
  end

  it "is offered once every scored shot of a finished session has a call" do
    shot
    uncalled = shot(called: false)
    expect(ModelUpdate.ready?(session)).to be false
    expect(ModelUpdate.left_to_review(session)).to eq(1)

    uncalled.update!(call_ring: 9, called_at: Time.current)
    expect(ModelUpdate.ready?(session)).to be true
    expect(ModelUpdate.ready?(create(:practice_session, user:))).to be false   # live
  end

  it "is never offered for the demo's replays, which aren't trained on" do
    demo = create(:practice_session, user: create(:user, username: "demo"), status: "ended", ended_at: Time.current)
    create(:shot, card: create(:card, practice_session: demo), call_ring: 9, called_at: Time.current)
    expect(ModelUpdate.ready?(demo)).to be false
  end

  it "exports, compares and retrains, keeping this session's numbers and the new model's" do
    2.times { shot }
    ENV["SPOTTER_ML_PYTHON"] = train_script.to_s

    state = ModelUpdate.for_session(run!(session))
    expect(state).to be_done
    expect(state.result["session"]).to include("agree" => 1, "model_agree" => 2, "model_n" => 2)
    expect(state.result["overall"]).to include("model" => { "agree" => 2, "n" => 2 })
    expect(state.result["trained"]).to include("version" => "20261114-0900", "trained_on" => 2)
    expect(engine.join("out/ml/dataset/index.jsonl").readlines.size).to eq(2)
  end

  it "says why when training fails" do
    shot
    ENV["SPOTTER_ML_PYTHON"] = train_script(fail: true).to_s

    state = ModelUpdate.for_session(run!(session))
    expect(state).to be_failed
    expect(state.error).to eq("training failed: RuntimeError: out of memory")
  end

  it "refuses while a session is live, or before every shot has a call" do
    shot(called: false)
    expect { ModelUpdate.start!(session) }.to raise_error(ModelUpdate::Busy, /every shot needs a call/)

    allow(EngineRunner).to receive(:running).and_return(session)
    expect { ModelUpdate.start!(session) }.to raise_error(ModelUpdate::Busy, /a session is running/)
  end

  it "marks an update cut off by an app restart as failed" do
    session.update_column(:model_update, { "status" => "running", "step" => "train" })
    expect(ModelUpdate.reconcile!(session)).to be_failed
    expect(ModelUpdate.running).to be_nil
  end
end
