require "rails_helper"

# Deleting in a LIVE session tells the engine (POST /forget), which had counted
# those shots: else its spoken "shot N" runs one ahead of the screen (2026-11-13).
# A stand-in engine records what arrives.
RSpec.describe "Deleting during a live session" do
  let(:user) { create(:user) }
  let(:engine) { TCPServer.new("127.0.0.1", 0) }
  let(:log) { Rails.root.join("tmp/live-delete-engine.log").tap { it.write("  forget deleted shots: POST /forget\n") } }
  let(:session) do
    create(:practice_session, user:, status: "shooting", stream_port: engine.addr[1], run_token: "tok-9", engine_log: log.to_s)
  end
  let!(:card1) { create(:card, practice_session: session, number: 1) }
  let!(:old_shot) { create(:shot, card: card1, number: 1, x_mm: 3.0, y_mm: 4.0) }
  let!(:card2) { create(:card, practice_session: session, number: 2) }
  let!(:shots) { (1..3).map { create(:shot, card: card2, number: it, x_mm: it.to_f, y_mm: -it.to_f) } }

  before do
    sign_in(user)
    allow(EngineRunner).to receive(:reconcile!)   # no real engine behind it
  end

  after do
    engine.close
    FileUtils.rm_f(log)
  end

  def engine_receives
    Thread.new do
      client = engine.accept
      head = +""
      head << client.gets until head.end_with?("\r\n\r\n")
      body = client.read(head[/Content-Length: (\d+)/i, 1].to_i)
      client.write("HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
      client.close
      { head:, body: JSON.parse(body) }
    end
  end

  it "tells the engine about a deleted shot on the card it is scoring" do
    received = engine_receives
    delete shot_path(shots[1])
    got = received.value
    expect(got[:head]).to start_with("POST /forget").and include("X-Spotter-Token: tok-9")
    expect(got[:body]["shots"]).to eq([ { "x_mm" => 2.0, "y_mm" => -2.0, "at" => shots[1].fired_at.to_f,
                                          "on_card" => true, "match" => false } ])
    expect(card2.shots.order(:number).pluck(:number)).to eq([ 1, 2 ])
  end

  it "tells it about an earlier card's shots: not on its card, only the match count" do
    old_shot.update!(stage: "match", match_number: 1)
    received = engine_receives
    delete practice_session_card_path(session, 1)
    expect(received.value[:body]["shots"]).to eq([ { "x_mm" => 3.0, "y_mm" => 4.0, "at" => old_shot.fired_at.to_f,
                                                     "on_card" => false, "match" => true } ])
  end

  it "leaves out a shot placed by hand (the engine never counted it), and an engine too old to understand" do
    shots[0].update!(pinpointed_at: Time.current)
    expect(EngineRunner).not_to receive(:post_to_engine)
    delete shot_path(shots[0])

    log.write("an older engine\n")
    delete shot_path(shots[2])
    expect(card2.shots.count).to eq(1)
  end

  describe "from the range screen itself (back=live)" do
    before { allow(EngineRunner).to receive(:forget!) }

    it "answers in place with a toast, not a page to go to" do
      delete shot_path(shots[2], back: "live"), as: :turbo_stream
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include('action="append"', "Deleted card 2, shot 3.")
      expect(card2.shots.count).to eq(2)

      delete practice_session_card_path(session, 1, back: "live"), as: :turbo_stream
      expect(response.body).to include("Deleted card 1 and its shot.")
    end

    it "says why, in place, for the card on the target" do
      delete practice_session_card_path(session, 2, back: "live"), as: :turbo_stream
      expect(response.body).to include("is on the target - change cards first", 'role="alert"')
      expect(session.cards.count).to eq(2)
    end

    it "puts Delete on the live screen's shots and earlier cards, their pages in a new tab" do
      get practice_session_path(session)
      page = Nokogiri::HTML(response.body)
      expect(page.css("form[action='#{shot_path(shots[0], back: "live")}']")).to be_present
      expect(page.css("form[action='#{practice_session_card_path(session, 1, back: "live")}']")).to be_present
      expect(page.css("a[href='#{shot_path(shots[0])}'][target='_blank']")).to be_present
      expect(page.css("a[href='#{practice_session_card_path(session, 1)}'][target='_blank']")).to be_present
    end
  end
end
