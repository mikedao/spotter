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

  it "is on by default, and stays off once turned off (on this device)" do
    session = create(:practice_session, user:, status: "shooting")
    allow(EngineRunner).to receive(:reconcile!)
    allow(EngineRunner).to receive(:snapshot).and_return(nil)
    visit new_session_path
    fill_in "Username", with: user.username
    fill_in "PIN", with: "1010"
    click_button "Sign in"
    visit practice_session_path(session)

    expect(page).to have_css("button", text: /Sound on|Tap anywhere for sound/)
    find("h1").click   # a tap anywhere starts it
    expect(page).to have_button("🔊 Sound on")
    click_button "🔊 Sound on"
    expect(page).to have_button("🔇 Sound off")
    visit practice_session_path(session)
    expect(page).to have_button("🔇 Sound off")   # remembered
  end

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

    # On by default; the browser may still want its first tap.
    click_button "🔈 Tap anywhere for sound" if page.has_button?("🔈 Tap anywhere for sound", wait: 1)
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
    # Each piece from the exported files in git (Heart has them) or rendered by the server.
    fetched = page.evaluate_script("performance.getEntriesByType('resource').map(e => e.name)")
                  .grep(%r{/voice-pieces/|/piece\?})
    expected = [ "shot 4", "9.6", "shot a touch low" ].map { Voice.piece_url(user.voice || Voice::DEFAULT, it) }
    expect(fetched.map { URI(it).request_uri }).to match_array(expected)
  end

  it "turns chatty mode on and off from the range screen, without a page load" do
    session = create(:practice_session, user:, status: "shooting")
    allow(EngineRunner).to receive(:reconcile!)
    allow(EngineRunner).to receive(:snapshot).and_return(nil)

    visit new_session_path
    fill_in "Username", with: user.username
    fill_in "PIN", with: "1010"
    click_button "Sign in"
    visit practice_session_path(session)

    click_button "🔈 Tap anywhere for sound" if page.has_button?("🔈 Tap anywhere for sound", wait: 1)
    click_button "💬 Quiet"
    expect(page).to have_button("💬 Chatty")
    expect(user.reload.chatty).to be(true)
    expect(page).to have_button("🔊 Sound on")   # still on: the page did not reload
    click_button "💬 Chatty"
    expect(page).to have_button("💬 Quiet")
    expect(user.reload.chatty).to be(false)
  end

  # 2026-11-13: the session-end summary was sent before the page's reload, but the
  # dev server delivered the reload FIRST: the page became the finished session (no
  # announcer) and the summary was never heard. The reload now waits a moment.
  it "still says the session summary when the reload arrives before it" do
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
    click_button "🔈 Tap anywhere for sound" if page.has_button?("🔈 Tap anywhere for sound", wait: 1)
    expect(page).to have_button("🔊 Sound on")

    session.update!(status: "ended", ended_at: Time.current)   # what the reload will show: no announcer
    html = Announcement.new(session, { "kind" => "chat", "gaps" => { "sentence" => 0.1, "comma" => 0.05 },
                                       "sentences" => [ { "pieces" => [ "that's the session" ] } ] })
                       .send(:payload).to_json
    page.execute_script(<<~JS, html)
      Turbo.renderStreamMessage('<turbo-stream action="refresh"></turbo-stream>')
      setTimeout(() => {
        const div = document.createElement("div")
        div.dataset.controller = "announcement"
        div.dataset.announcementPayloadValue = arguments[0]
        document.getElementById("announcements").appendChild(div)
      }, 300)
    JS

    expect(page).to have_css("[data-controller='announcer'][data-played='1']", wait: 5)   # said, before the reload
    expect(page).to have_no_css("[data-controller='announcer']", wait: 10)                 # then the finished page
    expect(page).to have_text("All ")
  end
end
