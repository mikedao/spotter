require "rails_helper"

# Any card of a session, reachable from the range screen, its shots deletable.
RSpec.describe "A session's cards" do
  let(:user) { create(:user) }
  let(:session) { create(:practice_session, user:, status: "ended", ended_at: Time.current) }
  let!(:card1) { create(:card, practice_session: session, number: 1).tap { |c| (1..3).each { |n| create(:shot, card: c, number: n, ring: 10 - n) } } }
  let!(:card2) { create(:card, practice_session: session, number: 2).tap { |c| create(:shot, card: c, number: 1, ring: 10) } }

  before { sign_in(user) }

  it "links each earlier card from the session page" do
    get practice_session_path(session)
    expect(response.body).to include(practice_session_card_path(session, 1))
  end

  it "shows an old card's target, numbers and shots, with a way to the next card" do
    get practice_session_card_path(session, 1)
    expect(response.body).to include("Card 1", "<svg", "card 1 of 2", "Card 2 →")
    expect(Nokogiri::HTML(response.body).css("button[aria-label^='Delete shot']").size).to eq(3)
  end

  it "shows a card holding an unscored capture (no shot number), in firing order" do
    create(:shot, card: card1, number: nil, status: "unscored", ring: nil, decimal_score: nil)
    get practice_session_card_path(session, 1)
    expect(response).to have_http_status(:ok)
    get practice_session_report_path(session)
    expect(response).to have_http_status(:ok)
  end

  it "deletes a shot from the card page and comes back to it" do
    shot = card1.shots.find_by(number: 2)
    delete shot_path(shot, back: "card")
    expect(response).to redirect_to(practice_session_card_path(session, 1))
    expect(card1.shots.order(:number).pluck(:number, :ring)).to eq([ [ 1, 9 ], [ 2, 7 ] ])
  end

  describe "deleting a card" do
    let!(:card3) { create(:card, practice_session: session, number: 3).tap { |c| create(:shot, card: c, number: 1, ring: 8) } }

    it "deletes it with its shots, and moves the later cards up a number" do
      get practice_session_card_path(session, 2)
      expect(response.body).to include("Delete card", "Delete card 2 and its 1 shot?")

      delete practice_session_card_path(session, 2)
      expect(response).to redirect_to(practice_session_path(session))
      expect(flash[:notice]).to eq("Deleted card 2 and its shot.")
      expect(session.cards.order(:number).map { [ it.number, it.shots.map(&:ring) ] }).to eq([ [ 1, [ 9, 8, 7 ] ], [ 2, [ 8 ] ] ])
      expect(Shot.where(card_id: card2.id)).to be_empty
    end

    it "counts a match's competition shots again from 1, its series with them" do
      match = create(:practice_session, user:, course: "match", status: "ended", ended_at: Time.current)
      n = 0
      (1..3).each do |number|
        c = create(:card, practice_session: match, number:)
        create(:shot, card: c, number: 1, stage: "sighter") if number == 1
        6.times { |i| n += 1; create(:shot, card: c, number: i + 2, stage: "match", match_number: n, series: (n - 1) / 10 + 1) }
      end

      delete practice_session_card_path(match, 2)   # match shots 7-12
      rows = match.shots.where(stage: "match").order(:match_number).pluck(:match_number, :series)
      expect(rows).to eq((1..12).map { [ it, (it - 1) / 10 + 1 ] })
      expect(match.cards.order(:number).pluck(:number)).to eq([ 1, 2 ])
      expect(match.shots.where(stage: "sighter").count).to eq(1)
    end

    it "mid-session: any earlier card, but not the one on the target" do
      session.update!(ended_at: nil, status: "shooting")
      allow(EngineRunner).to receive(:reconcile!)

      get practice_session_card_path(session, 3)
      expect(response.body).to include("On the target now")
      expect(response.body).not_to include("Delete card")
      delete practice_session_card_path(session, 3)
      expect(response).to redirect_to(practice_session_card_path(session, 3))
      expect(flash[:alert]).to include("on the target - change cards first")
      expect(session.cards.count).to eq(3)

      delete practice_session_card_path(session, 1)
      expect(session.cards.order(:number).map { it.shots.map(&:ring) }).to eq([ [ 10 ], [ 8 ] ])
      expect(session.reload.current_card.shots.map(&:ring)).to eq([ 8 ])   # new shots still land on it
    end

    it "is a 404 in another user's session" do
      other = create(:practice_session, status: "ended", ended_at: Time.current)
      create(:card, practice_session: other, number: 1)
      delete practice_session_card_path(other, 1)
      expect(response).to have_http_status(:not_found)
      expect(other.cards.count).to eq(1)
    end
  end

  it "is a 404 for a card that isn't there or another user's session" do
    get practice_session_card_path(session, 9)
    expect(response).to have_http_status(:not_found)
    get practice_session_card_path(create(:practice_session), 1)
    expect(response).to have_http_status(:not_found)
  end
end
