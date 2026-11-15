require "rails_helper"

# Announcer personalities: the list (mirrors the engine), the bank of lines they
# pick from, and the announcer that says them.
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

  it "is the user's only when her bank and the voices are here, and brings her voice" do
    user = build(:user, personality: "katey", voice: "bm_george")
    allow(Voice).to receive(:available?).and_return(false)
    expect(described_class.for(user)).to be_nil
    expect(Voice.for(user).id).to eq "bm_george"
    allow(Voice).to receive(:available?).and_return(true)
    expect(described_class.for(user).name).to eq "Katey"
    expect(Voice.for(user).id).to eq "af_nicole"
    expect(described_class.for(build(:user, personality: nil))).to be_nil
  end
end

RSpec.describe PersonalityBank do
  let(:session) { create(:practice_session) }

  it "has every situation the announcer asks for, and lines only the voice can say" do
    lines = described_class.lines("katey")
    steps = %w[ inner ten s95 s90 eight seven awful ]
    moments = %w[ tens_streak nine_run drop_after_run flyer card_done series_done session_end match_done halfway ] +
              [ "last series", "new card please", "sighter" ] + Commentary::DIRECTIONS.map { "tip #{it}" }
    engine = PersonalityAnnouncer::ENGINE_LINES.values + PersonalityAnnouncer::FLAGS.values + [ "flag found without a sound" ] +
             [ "penalty out of time", "penalty after the end", "penalty extra shot" ]
    expect(lines.keys).to include(*steps, *moments, *engine)
    steps.each { expect(lines[it].size).to be >= 100 }
    lines.values.flatten.each do |line|
      expect(line).to match(/\A[a-z0-9 .,'{}-]+\z/), line
      expect(line.scan(/\{(\w+)\}/).flatten - %w[ n total shots avg best ]).to be_empty, line
    end
  end

  it "never says anything about the goal, or anything near suicide" do
    text = described_class.lines("katey").values.flatten.join("\n")
    expect(text).not_to match(/\b(goal|pace|qualif\w*|(?<!free )trials?|olympics?|565)\b/)   # "free trial" is a joke, not the trials
    expect(text).not_to match(/\b(suicid\w*|kill (my|your)sel(f|ves)|delete (my|your)sel(f|ves)|self[- ]harm\w*|kys|kms|unalive\w*)\b/)
  end

  it "fills the placeholders, and skips lines it has no values for" do
    bank = described_class.new("katey", session)
    expect(bank.pick("card_done", total: "87")).to include("87").and(satisfy { !it.include?("{") })
    20.times { expect(bank.pick("session_end", shots: 40, avg: "9.2")).not_to include("{best}") }
  end

  it "lists every piece it can say, numbers filled in, each one a valid voice piece (rendered ahead)" do
    pieces = described_class.pieces("katey")
    expect(pieces.size).to be > 5000
    expect(pieces).to all(match(Voice.singleton_class.const_get(:PIECE)))
    expect(pieces).to include("best card 71").and(satisfy { |ps| ps.none? { it.include?("{") } })
  end

  it "never repeats a line in a session until the situation runs out" do
    bank = described_class.new("katey", session, random: Random.new(1))
    n = described_class.lines("katey")["ready"].size
    picked = Array.new(n) { bank.pick("ready") }
    expect(picked.uniq.size).to eq n
  end
end

RSpec.describe PersonalityAnnouncer do
  let(:user) { create(:user, personality: "katey", chatty: true) }
  let(:session) { create(:practice_session, user:, started_at: 20.minutes.ago, per_card: 10) }
  let(:card) { create(:card, practice_session: session, number: 1) }
  let(:shot) { create(:shot, card:, number: 4, ring: 9, decimal_score: 9.6, x_mm: 0.0, y_mm: -3.0, fired_at: Time.current) }
  let(:engine_line) do   # the engine's own announcement of that shot
    { "kind" => "ok", "plain_kind" => "ok", "sentences" => [ { "pieces" => [ "shot 4" ] }, { "pieces" => [ "9", "a touch low" ] } ] }
  end
  let(:bank) { PersonalityBank.lines("katey") }

  before do
    described_class.inline = true
    allow(Voice).to receive(:available?).and_return(true)
    @delivered = []
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to) { |*, **kw| @delivered << kw[:html] }
  end

  after { described_class.inline = false }

  def payloads = @delivered.map { JSON.parse(it[/data-announcement-payload-value="([^"]+)"/, 1].then { CGI.unescapeHTML(it) }) }
  def texts = payloads.map { |p| p["sentences"].map { |s| s.map(&:first).join(", ") }.join(". ") }
  def from_bank?(text, situation) = bank[situation].any? { text.include?(Commentary.split(it).last.last) }

  it "holds the engine's score line and says the score, the direction and her line once the shot arrives" do
    announcer = described_class.for(session)
    expect(announcer.announce!(engine_line)).to be true
    expect(@delivered).to be_empty
    announcer.shot!(shot)
    expect(texts.size).to eq 1
    expect(texts.first).to start_with("9, ").and satisfy { from_bank?(it, "s95") }
    expect(payloads.first).to include("supersede" => "shot", "gaps" => { "sentence" => 0.3, "comma" => 0.15 })
    expect(@delivered.join).to include("af_nicole")
  end

  it "says the engine's line after a while when no shot event follows" do
    described_class.inline = false
    stub_const("PersonalityAnnouncer::HOLD_S", 0.05)
    described_class.for(session).announce!(engine_line)
    sleep 0.3
    expect(texts.join).to include("shot 4")
  end

  it "says the engine's lines her way, and leaves the range officer standard" do
    announcer = described_class.for(session)
    expect(announcer.announce!({ "kind" => "ready", "plain_kind" => "ready", "sentences" => [ { "pieces" => [ "ready" ] } ] })).to be true
    expect(from_bank?(texts.last, "ready")).to be true
    expect(announcer.announce!({ "kind" => "ro", "plain_kind" => "ro", "sentences" => [ { "pieces" => [ "load" ] } ] })).to be false
  end

  it "picks the moment over the shot's step: three tens in a row" do
    3.times { |i| create(:shot, card:, number: i + 1, ring: 10, decimal_score: 10.2, x_mm: 0.5, y_mm: 0.0, fired_at: Time.current) }
    text = described_class.new(session.reload, Personality.find("katey")).shot_sentences(card.shots.find_by(number: 3)).map { it.join(", ") }.join(". ")
    expect(text).to start_with("10.2, ")
    expect(from_bank?(text, "tens_streak")).to be true
    expect(text).to include("three")
  end

  it "says the card total her way after ten shots, and asks for a new card" do
    10.times { |i| create(:shot, card:, number: i + 1, ring: 9, decimal_score: 9.3, x_mm: (-1)**i * 3.0, y_mm: 1.0, fired_at: Time.current) }
    text = described_class.new(session.reload, Personality.find("katey")).shot_sentences(card.shots.find_by(number: 10)).map { it.join(", ") }.join(". ")
    expect(text).to include("90")
    expect(from_bank?(text, "new card please")).to be true
    expect(text).not_to match(/better than the last|best one today/)
  end

  it "says a penalty and that it scores zero" do
    s = create(:shot, card:, number: 1, ring: 9, decimal_score: 9.3, x_mm: 0.0, y_mm: -3.0, fired_at: Time.current, penalty: "out of time")
    text = described_class.new(session.reload, Personality.find("katey")).shot_sentences(s).flatten.join(" ")
    expect(text).to include("zero")
  end

  it "replaces chatty mode, and says the end of the session herself" do
    10.times { |i| create(:shot, card:, number: i + 1, ring: 10, decimal_score: 10.2, x_mm: 0.5, y_mm: 0.0, fired_at: Time.current) }
    Commentary.after_event(session.reload, type: "shot", record: card.shots.last)
    expect(@delivered).to be_empty
    Commentary.after_event(session.reload, type: "session_ended")
    expect(from_bank?(texts.last, "session_end")).to be true
    expect(texts.last).to include("10").and include("10.0")
  end
end
