require "rails_helper"

# The live range screen plays announcements in the browser: Sound on, then each
# announcement's pieces fetched from the server and played in order.
RSpec.describe "Announcer on the range screen" do
  let(:user) { create(:user) }

  # A real (silent) WAV, so the browser can decode it like a voice piece.
  let(:wav) do
    Rails.root.join("tmp", "announcer-spec.wav").tap do |path|
      rate, samples = 24_000, 2_400
      data = "\0".b * (samples * 2)
      header = [ "RIFF", 36 + data.bytesize, "WAVE", "fmt ", 16, 1, 1, rate, rate * 2, 2, 16, "data", data.bytesize ]
                 .pack("a4Va4a4VvvVVvva4V")
      File.binwrite(path, header + data)
    end
  end

  after { FileUtils.rm_f(wav) }

  it "plays an announcement once sound is on, fetching each piece" do
    session = create(:practice_session, user:, status: "shooting")
    allow(EngineRunner).to receive(:reconcile!)
    allow(EngineRunner).to receive(:snapshot).and_return(nil)
    allow(Voice).to receive(:available?).and_return(true)
    allow(Voice).to receive(:piece!).and_return(wav)

    visit new_session_path
    fill_in "Username", with: user.username
    fill_in "PIN", with: "1010"
    click_button "Sign in"
    visit practice_session_path(session)

    click_button "🔇 Sound off"
    expect(page).to have_button("🔊 Sound on")

    # What a Turbo broadcast appends (Announcement#deliver!).
    html = Announcement.new(session, { "kind" => "ok", "plain_kind" => "ok", "gaps" => { "sentence" => 0.1, "comma" => 0.05 },
                                       "sentences" => [ { "pieces" => [ "shot 4" ] }, { "pieces" => [ "9.6", "shot a touch low" ] } ] })
                       .send(:payload).to_json
    page.execute_script(<<~JS, html)
      const div = document.createElement("div")
      div.dataset.controller = "announcement"
      div.dataset.announcementPayloadValue = arguments[0]
      document.getElementById("announcements").appendChild(div)
    JS

    expect(page).to have_css("[data-controller='announcer'][data-played='1']", wait: 5)
    fetched = page.evaluate_script("performance.getEntriesByType('resource').map(e => e.name).filter(n => n.includes('/piece?'))")
    expect(fetched.map { CGI.unescape(it[/text=([^&]+)/, 1].tr("+", " ")) }).to contain_exactly("shot 4", "9.6", "shot a touch low")
  end
end
