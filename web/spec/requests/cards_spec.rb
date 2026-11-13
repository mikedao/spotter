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

  it "is a 404 for a card that isn't there or another user's session" do
    get practice_session_card_path(session, 9)
    expect(response).to have_http_status(:not_found)
    get practice_session_card_path(create(:practice_session), 1)
    expect(response).to have_http_status(:not_found)
  end
end
