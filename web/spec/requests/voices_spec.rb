require "rails_helper"

RSpec.describe "Announcer voice" do
  let(:user) { create(:user) }

  before { sign_in(user) }

  it "lists every voice in Settings with the user's choice selected" do
    user.update!(voice: "bm_george")
    get settings_path
    expect(response.body).to include("Announcer voice", "George", "Heart", voice_sample_path("af_heart"))
    expect(response.body).to match(/value="bm_george"[^>]*checked|checked[^>]*value="bm_george"/)
  end

  it "saves the choice and prepares the voice in the background" do
    allow(Voice).to receive(:prewarm!)
    patch voice_path, params: { voice: "bf_emma" }
    expect(user.reload.voice).to eq "bf_emma"
    expect(Voice).to have_received(:prewarm!).with("bf_emma")
    follow_redirect!
    expect(response.body).to include("Your announcer is now Emma")
  end

  describe "chatty mode's remarks" do
    let(:pieces) { Commentary.pieces(user) }

    before do
      allow(Voice).to receive(:available?).and_return(true)
      allow(Voice).to receive(:preparing?).and_return(false)
      allow(Voice).to receive(:chatty_built_in?).and_return(false)
      allow(Voice).to receive(:chatty_built_in?).with("af_bella", anything).and_return(true)
    end

    it "says which voices have them built in, and offers to prepare the user's own" do
      allow(Voice).to receive(:chatty_readiness).and_return(Voice::ChattyReadiness.new(ready: 8, total: 1935))
      get settings_path
      expect(response.body).to include("💬 built in", "built into Bella only", "made on the fly",
                                       "Prepare chatty remarks now", "8 of 1,935 ready")
    end

    it "says nothing needs preparing in a built-in voice" do
      user.update!(voice: "af_bella")
      get settings_path
      expect(response.body).to include("built into Bella: they play straight away")
      expect(response.body).not_to include("Prepare chatty remarks now")
    end

    it "shows progress while they are being prepared" do
      allow(Voice).to receive(:preparing?).and_return(true)
      allow(Voice).to receive(:chatty_readiness).and_return(Voice::ChattyReadiness.new(ready: 900, total: 1935))
      get settings_path
      expect(response.body).to include("Preparing in the background: 900 of 1,935 ready", "11 minutes")
      expect(response.body).not_to include("Prepare chatty remarks now")
    end

    it "says when all are prepared" do
      allow(Voice).to receive(:chatty_readiness).and_return(Voice::ChattyReadiness.new(ready: 1935, total: 1935))
      get settings_path
      expect(response.body).to include("All 1,935 remarks are prepared in Heart")
    end

    it "prepares them in the user's voice, in the background" do
      allow(Voice).to receive(:prewarm!)
      user.update!(voice: "bf_emma")
      post prepare_voice_path
      expect(Voice).to have_received(:prewarm!).with("bf_emma", extra: pieces)
      follow_redirect!
      expect(response.body).to include("Preparing Emma&#39;s chatty remarks")
    end

    it "refuses when the voices aren't set up" do
      allow(Voice).to receive(:available?).and_return(false)
      allow(Voice).to receive(:prewarm!)
      post prepare_voice_path
      expect(Voice).not_to have_received(:prewarm!)
    end
  end

  it "refuses a voice that isn't one of them" do
    patch voice_path, params: { voice: "--help" }
    expect(user.reload.voice).to be_nil
  end

  it "plays a voice's sample, and 404s an unknown one" do
    wav = Rails.root.join("tmp", "voice-spec.wav")
    File.binwrite(wav, "RIFFfake")
    allow(Voice).to receive(:sample_path).and_call_original
    allow(Voice).to receive(:sample_path).with("af_heart").and_return(wav)
    get voice_sample_path("af_heart")
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq "audio/wav"

    get voice_sample_path("nobody")
    expect(response).to have_http_status(:not_found)
  ensure
    FileUtils.rm_f(wav)
  end

  it "has the engine hand its announcements to the range screen instead of speaking them" do
    session = create(:practice_session, user:, camera: "0")
    command = EngineRunner.command(session)
    expect(command.each_cons(2)).to include([ "--announce", "web" ])
    expect(command).not_to include("--voice")
  end

  it "serves one announcement piece in a voice, and refuses what isn't a piece" do
    wav = Rails.root.join("tmp", "voice-piece-spec.wav")
    File.binwrite(wav, "RIFFfake")
    allow(Voice).to receive(:piece!).and_call_original
    allow(Voice).to receive(:piece!).with("af_heart", "shot 4").and_return(wav)
    get voice_piece_path("af_heart", text: "shot 4")
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq "audio/wav"

    get voice_piece_path("af_heart", text: "$(rm -rf /)")
    expect(response).to have_http_status(:not_found)
    get voice_piece_path("nobody", text: "shot 4")
    expect(response).to have_http_status(:not_found)
  ensure
    FileUtils.rm_f(wav)
  end

  it "plays a known piece from the exported files in git, and asks the server only for the rest" do
    allow(Voice).to receive(:exported_dir).and_return(Rails.root.join("tmp", "voice-pieces-spec"))
    FileUtils.mkdir_p(Voice.exported_dir.join("af_heart"))
    File.binwrite(Voice.exported_dir.join("af_heart", "shot_4.m4a"), "fake")
    expect(Voice.piece_url("af_heart", "shot 4")).to eq("/voice-pieces/af_heart/shot_4.m4a")
    expect(Voice.piece_url("af_heart", "a brand new line")).to eq("/voices/af_heart/piece?text=a+brand+new+line")
  ensure
    FileUtils.rm_rf(Rails.root.join("tmp", "voice-pieces-spec"))
  end

  it "names a cached piece the way the voice helper does" do
    expect(Voice.piece_path("af_heart", "that's 10").basename.to_s).to eq("that_s_10.wav")
    expect(Voice.piece_path("af_heart", "10.9").basename.to_s).to eq("10_9.wav")
  end

  it "turns diagnostic mode on and off in Settings" do
    get settings_path
    expect(response.body).to include("Diagnostic mode")
    patch settings_path, params: { user: { diagnostic_announcements: "1" } }
    expect(user.reload.diagnostic_announcements).to be(true)
    patch settings_path, params: { user: { diagnostic_announcements: "0" } }
    expect(user.reload.diagnostic_announcements).to be(false)
    patch settings_path, params: { user: { chatty: "1" } }
    expect(user.reload.chatty).to be(true)
    expect(user.diagnostic_announcements).to be(false)   # left as it was
  end
end
