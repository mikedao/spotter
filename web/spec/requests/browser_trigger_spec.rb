require "rails_helper"

# The range screen as the shot trigger: the browser posts each sharp sound, the
# web app relays it to the engine's live view (POST /trigger) with the session's
# token. A stand-in engine records what arrives.
RSpec.describe "The browser as the shot trigger" do
  let(:user) { create(:user) }
  let(:engine) { TCPServer.new("127.0.0.1", 0) }
  let(:session) do
    create(:practice_session, user:, mic: CameraProbe::BROWSER_MIC, stream_port: engine.addr[1], run_token: "tok-123")
  end

  before do
    sign_in(user)
    allow(EngineRunner).to receive(:reconcile!)   # no real engine behind it
  end

  after { engine.close }

  # Answers one request with `status`, and returns what it was sent.
  def engine_answers(status)
    Thread.new do
      client = engine.accept
      head = +""
      head << client.gets until head.end_with?("\r\n\r\n")
      body = client.read(head[/Content-Length: (\d+)/i, 1].to_i)
      client.write("HTTP/1.1 #{status}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
      client.close
      { head:, body: JSON.parse(body) }
    end
  end

  it "relays a sound to the engine with the session's token, timed by how long ago it began" do
    received = engine_answers("204 No Content")
    post trigger_practice_session_path(session), params: { ago_ms: 140, over_db: 70.2, len_ms: 310 }, as: :json
    expect(response).to have_http_status(:no_content)

    got = received.value
    expect(got[:head]).to start_with("POST /trigger").and include("X-Spotter-Token: tok-123")
    expect(got[:body]).to eq("ago_ms" => 140.0, "over_db" => 70.2, "len_ms" => 310.0)
  end

  it "says so when the engine refuses it, or the session doesn't listen through the browser" do
    engine_answers("403 Forbidden")
    post trigger_practice_session_path(session), params: { ago_ms: 0, over_db: 70, len_ms: 300 }, as: :json
    expect(response).to have_http_status(:conflict)

    session.update!(mic: "Razer Kiyo")
    post trigger_practice_session_path(session), params: { ago_ms: 0, over_db: 70, len_ms: 300 }, as: :json
    expect(response).to have_http_status(:conflict)
  end

  it "puts the microphone on the range screen only for such a session" do
    get practice_session_path(session)
    expect(response.body).to include('data-controller="browser-trigger"', trigger_practice_session_path(session))

    session.update!(mic: "Razer Kiyo")
    get practice_session_path(session)
    expect(response.body).not_to include('data-controller="browser-trigger"')
  end

  it "is another user's session: not found" do
    other = create(:practice_session, user: create(:user), mic: CameraProbe::BROWSER_MIC)
    post trigger_practice_session_path(other), params: { ago_ms: 0, over_db: 70, len_ms: 300 }, as: :json
    expect(response).to have_http_status(:not_found)
  end
end
