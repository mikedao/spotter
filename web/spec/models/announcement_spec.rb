require "rails_helper"

# What the range screen plays after an engine event: diagnostic sentences only
# in diagnostic mode.
RSpec.describe Announcement do
  let(:user) { create(:user, voice: "bf_emma") }
  let(:session) { create(:practice_session, user:) }

  # The engine's "announce" event for "shot 4. 9.6, shot a touch low. line call".
  let(:shot) do
    { "kind" => "check", "plain_kind" => "ok", "gaps" => { "sentence" => 0.55, "comma" => 0.25 },
      "sentences" => [ { "pieces" => [ "shot 4" ], "diagnostic" => false },
                       { "pieces" => [ "9.6", "shot a touch low" ], "diagnostic" => false },
                       { "pieces" => [ "line call", "found without a sound" ], "diagnostic" => true } ] }
  end

  def texts(announcement) = announcement.payload[:sentences].map { |s| s.map(&:first) }

  it "says only the number, score and direction with diagnostic mode off, with the plain tone" do
    a = described_class.new(session, shot)
    expect(texts(a)).to eq([ [ "shot 4" ], [ "9.6", "shot a touch low" ] ])
    expect(a.payload[:kind]).to eq("ok")
    expect(a.payload[:sentences].first.first.last).to eq("/voices/bf_emma/piece?text=shot+4").or eq("/voice-pieces/bf_emma/shot_4.m4a")
  end

  it "adds why the shot is worth a look with diagnostic mode on" do
    user.update!(diagnostic_announcements: true)
    a = described_class.new(session, shot)
    expect(texts(a).last).to eq([ "line call", "found without a sound" ])
    expect(a.payload[:kind]).to eq("check")
  end

  it "says nothing when everything was diagnostic" do
    geometry = { "kind" => "check", "plain_kind" => nil,
                 "sentences" => [ { "pieces" => [ "geometry warning", "consider a fresh card" ], "diagnostic" => true } ] }
    expect(described_class.new(session, geometry).playable?).to be(false)
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
    described_class.new(session, geometry).deliver!
    expect(Turbo::StreamsChannel).not_to have_received(:broadcast_append_to)
  end

  it "pushes a playable one to the session's range screens" do
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
    described_class.new(session, shot).deliver!
    expect(Turbo::StreamsChannel).to have_received(:broadcast_append_to)
      .with(session, target: "announcements", html: a_string_including('data-controller="announcement"'))
  end

  it "plays the committed voice files even where the voice can't be rendered, else the browser's voice" do
    allow(Voice).to receive(:available?).and_return(false)
    allow(Voice).to receive(:exported_path).and_return(Pathname(__FILE__))   # every piece "in git"
    expect(described_class.new(session, shot).payload[:kokoro]).to be(true)
    allow(Voice).to receive(:exported_path).and_return(Pathname("/nonexistent.m4a"))
    expect(described_class.new(session, shot).payload[:kokoro]).to be(false)
  end

  describe ".spoken_direction" do
    def said(decimal, direction = "low left") = described_class.spoken_direction(Struct.new(:direction, :final_decimal).new(direction, decimal))

    # Run the engine's voicelines.spoken_direction many times: every phrasing it can pick.
    def engine_phrases(decimal)
      code = "import json, voicelines as v; print(json.dumps(sorted({v.spoken_direction('low left', #{decimal}) for _ in range(400)})))"
      out, status = Open3.capture2(EngineRunner.python, "-c", code, chdir: EngineRunner.engine_dir.to_s)
      skip "engine Python not available" unless status.success?
      JSON.parse(out)
    end

    it "words how far out exactly as the engine does, band by band (engine/directions.json)" do
      [ 10.3, 9.9, 9.5, 9.4, 9.0, 8.9, 8.0, 7.0, 6.0, 5.9, 0.0 ].each do |decimal|
        ruby = Array.new(400) { said(decimal) }.uniq.sort
        expect(ruby).to eq(engine_phrases(decimal)), "band for #{decimal}"
      end
    end

    it "steps from just to way out, and says center for an inner ten" do
      expect(described_class.direction_bands.map { it["from"] }).to eq([ 10.0, 9.5, 9.0, 8.0, 7.0, 6.0, 0.0 ])
      expect(said(9.6, "center")).to eq("center")
      expect(Array.new(100) { said(9.6) }).to all(end_with("low left"))
      expect(described_class.direction_bands.flat_map { it["phrases"] }).to all(match(/\A[a-z' ]+\{dir\}\z/))
    end
  end

  describe ".spoken_score" do
    def said(decimal, ring) = described_class.spoken_score(Struct.new(:final_decimal, :final_ring).new(decimal, ring))

    it "says the ring below 10 and the decimal from 10 up, as the engine does (phase1._spoken_score)" do
      expect([ said(9.6, 9), said(8.0, 8), said(0.0, 0), said(10.0, 10), said(10.7, 10) ]).to eq [ "9", "8", "0", "10.0", "10.7" ]
      out, status = Open3.capture2(EngineRunner.python, "-c",
                                   "import phase1; print('|'.join(phase1._spoken_score({'decimal': d, 'integer': int(d)}) for d in (9.6, 8.0, 0.0, 10.0, 10.7)))",
                                   chdir: EngineRunner.engine_dir.to_s)
      skip "engine Python not available" unless status.success?
      expect(out.strip.split("|")).to eq [ "9", "8", "0", "10.0", "10.7" ]
    end
  end
end
