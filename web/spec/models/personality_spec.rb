require "rails_helper"

# Announcer personalities: the list (mirrors the engine), the facts a personality
# is given (exactly as its model was trained), and the announcer that asks it and
# falls back to the standard announcement.
RSpec.describe Personality do
  let(:voice_dir) { EngineRunner.engine_dir.join("voice") }

  def engine_python(code)
    out, status = Open3.capture2(EngineRunner.python, "-c", code, chdir: voice_dir.to_s)
    skip "engine Python not available" unless status.success?
    JSON.parse(out)
  end

  it "offers exactly the engine's personalities (engine/voice/personalities)" do
    engine = engine_python(<<~PY)
      import json, pathlib, importlib
      out = {}
      for f in sorted(pathlib.Path("personalities").glob("*.py")):
          if f.stem != "__init__":
              m = importlib.import_module(f"personalities.{f.stem}")
              out[f.stem] = [m.TITLE, m.VOICE, m.DESCRIPTION]
      print(json.dumps(out))
    PY
    expect(described_class::ALL.transform_values { [ it.name, it.voice, it.description ] }).to eq engine
    expect(described_class.all.map(&:voice)).to all(satisfy { Voice.valid?(it) })
  end

  it "is the user's only when its model is trained here, and brings its voice" do
    user = build(:user, personality: "katey", voice: "bm_george")
    allow(described_class).to receive(:trained?).and_return(false)
    expect(described_class.for(user)).to be_nil
    expect(Voice.for(user).id).to eq "bm_george"
    allow(described_class).to receive(:trained?).and_return(true)
    expect(described_class.for(user).name).to eq "Katey"
    expect(Voice.for(user).id).to eq "af_nicole"
    expect(described_class.for(build(:user, personality: nil))).to be_nil
  end
end

RSpec.describe PersonalityFacts do
  let(:user) { create(:user) }
  let(:session) { create(:practice_session, user:, started_at: 30.minutes.ago, per_card: 10) }
  let(:card) { create(:card, practice_session: session, number: 1) }

  def fire(*decimals, at: [ 0.0, -3.0 ], **attrs)
    decimals.map do |d|
      n = (card.shots.maximum(:number) || 0) + 1
      create(:shot, card:, number: n, ring: d.to_i, decimal_score: d, x_mm: at[0], y_mm: at[1],
                    fired_at: session.started_at + n.minutes, **attrs)
    end.last
  end

  # No extras (previous shot, time...): their chance never comes up.
  def facts_for(shot, chance: 1.0) = described_class.new(session.reload, random: Random.new(1).tap { |r| def r.rand = 0.99 if chance == 1.0 }).for_shot(shot)
  def parse(text) = text.lines.to_h { it.chomp.split(": ", 2) }

  it "says numbers exactly as the model's training did (talk.py words / decimal_words)" do
    nums = [ 0, 7, 13, 20, 42, 94, 100, 541, 600 ]
    decs = [ 0.0, 5.9, 9.0, 9.6, 10.0, 10.9 ]
    engine = begin
      out, status = Open3.capture2(EngineRunner.python, "-c",
                                   "import json, talk; print(json.dumps([[talk.words(n) for n in #{nums}], [talk.decimal_words(d) for d in #{decs}]]))",
                                   chdir: EngineRunner.engine_dir.join("voice").to_s)
      skip "engine Python not available" unless status.success?
      JSON.parse(out)
    end
    expect([ nums.map { described_class.words(it) }, decs.map { described_class.decimal_words(it) } ]).to eq engine
  end

  it "uses only the facts, and the wording of them, the model was trained on" do
    out, status = Open3.capture2(EngineRunner.python, "-c", <<~PY, chdir: EngineRunner.engine_dir.join("voice").to_s)
      import json, random, talk
      b = talk.Builder(talk.personality("katey"), random.Random(3))
      keys, far = set(), set()
      for _ in range(3000):
          facts = b.example()["messages"][1]["content"]
          for line in facts.splitlines():
              k, v = line.split(": ", 1)
              keys.add(k)
              if k == "how far": far.add(v)
      print(json.dumps([sorted(keys), sorted(far)]))
    PY
    skip "engine Python not available" unless status.success?
    trained_keys, trained_far = JSON.parse(out)
    fire(9.1, 9.4, 9.2, 9.5, 10.1, 10.2, 10.3, 9.9, 8.7)
    shots = [ fire(6.4), fire(10.5, at: [ 0.0, 0.5 ], inner_ten: true) ]
    texts = shots.map { facts_for(it, chance: 0.0) } + card.shots.map { described_class.new(session.reload, random: Random.new(it.id)).for_shot(it) }
    texts.each do |text|
      facts = parse(text)
      expect(facts.keys - [ "event" ]).to all(be_in(trained_keys)), text
      expect(trained_far).to include(facts["how far"])
    end
  end

  it "gives the shot, the score and how far in words" do
    facts = parse(facts_for(fire(9.6)))
    expect(facts).to include("event" => "shot", "shot" => "one", "score" => "nine six",
                             "how far" => "nine five to nine nine", "direction" => "low")
    expect(parse(facts_for(fire(10.4, at: [ 0.0, 0.5 ], inner_ten: true)))).to include("how far" => "inner ten", "direction" => "center")
  end

  it "names the moment as chatty mode sees it: a streak, a bad shot after a run, the card total" do
    fire(9.2, 10.1, 10.3)
    expect(parse(facts_for(fire(10.2)))["moment"]).to eq "three tens in a row"
    fire(9.1, at: [ 3.0, 0.0 ])
    fire(9.3, at: [ -3.0, 0.0 ])                  # spread out: not three in a row on one side
    expect(parse(facts_for(fire(7.2)))["moment"]).to eq "after six in a row in the nine or better"
    last = fire(9.0, 9.0, 9.0)
    expect(last.number).to eq 10
    facts = parse(facts_for(last))
    expect(facts).to include("card" => "done, total ninety one", "compared" => "first today", "new card" => "yes")
  end

  it "maps the engine's lines to hers, and leaves the range officer alone" do
    f = described_class.new(session)
    expect(f.for_engine_line([ [ "new card", "ready" ] ])).to eq "event: new card"
    expect(f.for_engine_line([ [ "ready" ] ])).to eq "event: ready"
    expect(f.for_engine_line([ [ "load" ] ])).to be_nil
  end

  it "sums up the session" do
    fire(*Array.new(20) { 9.3 })
    expect(parse(described_class.new(session.reload).for_session_end))
      .to eq("event" => "session over", "shots" => "twenty", "average" => "nine oh", "best card" => "ninety")
  end
end

RSpec.describe PersonalityAnnouncer do
  let(:user) { create(:user, personality: "katey", chatty: true) }
  let(:session) { create(:practice_session, user:, started_at: 20.minutes.ago) }
  let(:card) { create(:card, practice_session: session, number: 1) }
  let(:shot) { create(:shot, card:, number: 4, ring: 9, decimal_score: 9.6, x_mm: 0.0, y_mm: -3.0, fired_at: Time.current) }
  let(:engine_line) do   # the engine's own announcement of that shot
    { "kind" => "ok", "plain_kind" => "ok", "sentences" => [ { "pieces" => [ "shot 4" ] }, { "pieces" => [ "9.6", "a touch low" ] } ] }
  end
  let(:katey) { { "ok" => true, "sentences" => [ [ "nine six", "a touch low" ], [ "almost", "babe" ] ] } }

  before do
    described_class.inline = true
    allow(Personality).to receive_messages(trained?: true, alive?: true)
    @delivered = []
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to) { |*, **kw| @delivered << kw[:html] }
  end

  after { described_class.inline = false }

  def said = @delivered

  it "holds the engine's score line and says hers once the shot arrives" do
    allow(Personality).to receive(:say).and_return(katey)
    announcer = described_class.for(session)
    expect(announcer.announce!(engine_line)).to be true
    expect(Turbo::StreamsChannel).not_to have_received(:broadcast_append_to)
    announcer.shot!(shot)
    expect(Personality).to have_received(:say).with("katey", a_string_including("score: nine six"), budget_s: 2.5)
    expect(said.join).to include("almost").and include("af_nicole")
    payload = JSON.parse(said.join[/data-announcement-payload-value="([^"]+)"/, 1].gsub("&quot;", '"'))
    expect(payload).to include("supersede" => "shot", "gaps" => { "sentence" => 0.3, "comma" => 0.15 })
  end

  it "says the engine's own line when she can't" do
    allow(Personality).to receive(:say).and_return({ "ok" => false, "why" => [ "score" ] })
    announcer = described_class.for(session)
    announcer.announce!(engine_line)
    announcer.shot!(shot)
    expect(said.join).to include("shot 4").and include("a touch low")
  end

  it "says the engine's line after a while when no shot event follows" do
    described_class.inline = false
    stub_const("PersonalityAnnouncer::HOLD_S", 0.05)
    described_class.for(session).announce!(engine_line)
    sleep 0.3
    expect(said.join).to include("shot 4")
  end

  it "says the engine's lines her way, and leaves the range officer standard" do
    allow(Personality).to receive(:say).and_return({ "ok" => true, "sentences" => [ [ "ready", "trouble" ] ] })
    announcer = described_class.for(session)
    expect(announcer.announce!({ "kind" => "ready", "plain_kind" => "ready", "sentences" => [ { "pieces" => [ "ready" ] } ] })).to be true
    expect(Personality).to have_received(:say).with("katey", "event: ready", budget_s: 2.5)
    expect(announcer.announce!({ "kind" => "ro", "plain_kind" => "ro", "sentences" => [ { "pieces" => [ "load" ] } ] })).to be false
  end

  it "replaces chatty mode, and says the end of the session herself" do
    allow(Personality).to receive(:say).and_return({ "ok" => true, "sentences" => [ [ "that's it" ] ] })
    10.times { |i| create(:shot, card:, number: i + 1, ring: 10, decimal_score: 10.2, x_mm: 0.5, y_mm: 0.0, fired_at: Time.current) }
    Commentary.after_event(session.reload, type: "shot", record: card.shots.last)
    expect(Personality).not_to have_received(:say)
    Commentary.after_event(session.reload, type: "session_ended")
    expect(Personality).to have_received(:say).with("katey", a_string_including("event: session over"), budget_s: 2.5)
  end

  it "isn't used, and starts her, while her process isn't running" do
    allow(Personality).to receive(:alive?).and_return(false)
    allow(Personality).to receive(:ensure!)
    expect(described_class.for(session)).to be_nil
    expect(Personality).to have_received(:ensure!).with("katey")
  end
end
