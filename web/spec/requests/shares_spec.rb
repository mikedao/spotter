require "rails_helper"

RSpec.describe "Sharing to CompetitiveShooter.org" do
  let(:key) { "csk_#{'b' * 32}" }
  let(:user) { create(:user, cso_api_key: key) }
  let(:session) do
    s = create(:practice_session, user:, status: "ended", ended_at: Time.current)
    card = create(:card, practice_session: s, number: 1)
    10.times { |i| create(:shot, card:, number: i + 1, ring: 9, x_mm: i.to_f, y_mm: 2.0) }
    s
  end

  before { sign_in(user) }

  it "previews every picture with the colors and topics pre-picked" do
    get new_share_path(session_ids: [ session.id ])
    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    expect(page.css("img[data-kind]").map { it["data-kind"] }).to eq(SharePicture::KINDS.keys)
    expect(page.css("input[name='pictures[]'][checked]").size).to eq(4)
    expect(page.at_css("input[name='topics[]'][value='international-issf-pistol']")["checked"]).to be_present
    expect(page.at_css("input[name=colors][value=midnight]")["checked"]).to be_present
  end

  it "serves a picture as it will be posted", if: system("which rsvg-convert > /dev/null 2>&1") do
    get picture_share_path(kind: "scorecard", session_ids: [ session.id ], colors: "forest")
    expect(response.media_type).to eq("image/jpeg")
    expect(response.body.byteslice(0, 2).bytes).to eq([ 0xFF, 0xD8 ])
  end

  it "posts the picked pictures, remembers the post and the colors, and links it on the session" do
    client = instance_double(CompetitiveShooter)
    allow(CompetitiveShooter).to receive(:new).with(key).and_return(client)
    allow_any_instance_of(SharePicture).to receive(:jpeg).and_return("jpeg".b)
    expect(client).to receive(:post!) do |body:, topics:, images:|
      expect(body).to eq("Clean day")
      expect(topics).to eq([ "international-issf-pistol" ])
      expect(images.map(&:first)).to eq([ "spotter-hero.jpg", "spotter-stats.jpg" ])
      { "id" => "p1", "url" => "https://competitiveshooter.org/posts/p1" }
    end

    post share_path, params: { session_ids: [ session.id ], pictures: %w[ hero stats ], colors: "crimson", identity: 1,
                               body: "Clean day", topics: %w[ international-issf-pistol made-up ] }
    expect(response).to redirect_to(practice_session_path(session, anchor: "export"))
    expect(user.shared_posts.sole).to have_attributes(post_id: "p1", session_ids: [ session.id ], pictures: %w[ hero stats ])
    expect(user.reload.share_colors).to eq("crimson")

    get practice_session_path(session)
    expect(response.body).to include("Posted to CompetitiveShooter.org", "https://competitiveshooter.org/posts/p1")
  end

  it "shows the site's refusal and keeps what was typed" do
    allow_any_instance_of(SharePicture).to receive(:jpeg).and_return("jpeg".b)
    allow_any_instance_of(CompetitiveShooter).to receive(:post!).and_raise(CompetitiveShooter::Error, "That's CompetitiveShooter.org's limit of 10 posts an hour.")
    post share_path, params: { session_ids: [ session.id ], pictures: %w[ hero ], body: "Keep me" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("10 posts an hour", "Keep me")
    expect(SharedPost.count).to eq(0)
  end

  it "refuses with no picture picked" do
    post share_path, params: { session_ids: [ session.id ] }
    expect(response.body).to include("Pick at least one picture")
  end

  it "won't post without a key, but still shows the pictures" do
    user.update!(cso_api_key: nil)
    get new_share_path(session_ids: [ session.id ])
    expect(response.body).to include("add your CompetitiveShooter.org API key")
    expect(Nokogiri::HTML(response.body).at_css("form[action='/share'] button[type=submit]")["disabled"]).to be_present
  end

  it "sends a live session back with a reason" do
    live = create(:practice_session, user:)
    get new_share_path(session_ids: [ live.id ]), headers: { "HTTP_REFERER" => practice_session_url(live) }
    expect(response).to redirect_to(practice_session_url(live))
    expect(flash[:alert]).to match(/finished/)
  end

  it "is a 404 for another user's session" do
    other = create(:practice_session, status: "ended", ended_at: Time.current)
    get new_share_path(session_ids: [ other.id ])
    expect(response).to have_http_status(:not_found)
  end

  it "shares a hand-picked day from the journal" do
    session
    get journal_path
    expect(response.body).to include("Share selected to CompetitiveShooter.org")
  end

  describe "the key in Settings" do
    it "saves a key, shows only its hint, and removes it" do
      patch competitive_shooter_setting_path, params: { user: { cso_api_key: " csk_#{'c' * 28}WXYZ " } }
      expect(user.reload.cso_api_key).to eq("csk_#{'c' * 28}WXYZ")
      get settings_path
      expect(response.body).to include("csk_…WXYZ")
      expect(response.body).not_to include("c" * 28)

      patch competitive_shooter_setting_path, params: { remove: 1 }
      expect(user.reload.cso_api_key).to be_nil
    end

    it "refuses something that isn't a key" do
      patch competitive_shooter_setting_path, params: { user: { cso_api_key: "password123" } }
      expect(flash[:alert]).to match(/csk_/)
      expect(user.reload.cso_api_key).to eq(key)
    end
  end
end
