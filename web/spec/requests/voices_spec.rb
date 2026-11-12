require "rails_helper"

RSpec.describe "Announcer voice" do
  let(:user) { create(:user) }

  before { sign_in(user) }

  it "lists every voice on Rig setup with the user's choice selected" do
    user.update!(voice: "bm_george")
    get setup_path
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

  it "starts the engine with the user's voice when the voices are set up" do
    user.update!(voice: "am_michael")
    allow(Voice).to receive(:available?).and_return(true)
    session = create(:practice_session, user:, camera: "0")
    expect(EngineRunner.command(session).each_cons(2)).to include([ "--voice", "am_michael" ])
  end
end
