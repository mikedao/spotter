require "rails_helper"

# Deleting a shot that wasn't a real one.
RSpec.describe "Deleting a shot" do
  let(:user) { create(:user) }
  let(:session) { create(:practice_session, user:, status: "ended", ended_at: Time.current) }
  let(:card) { create(:card, practice_session: session, number: 1) }
  let!(:shots) { (1..4).map { create(:shot, card:, number: it, ring: 10 - it) } }

  before { sign_in(user) }

  it "deletes it from the shot page and renumbers the later shots on the card" do
    get shot_path(shots[1])
    expect(response.body).to include("Delete shot", "Delete card 1, shot 2?")

    delete shot_path(shots[1])
    expect(response).to redirect_to(practice_session_path(session))
    expect(flash[:notice]).to eq("Deleted card 1, shot 2.")
    expect(card.shots.order(:number).pluck(:number, :ring)).to eq([ [ 1, 9 ], [ 2, 7 ], [ 3, 6 ] ])
  end

  it "renumbers a match's competition shots and recounts its series; sighters and a final's windows stay" do
    match = create(:practice_session, user:, course: "match", status: "ended", ended_at: Time.current)
    c = create(:card, practice_session: match, number: 1)
    create(:shot, card: c, number: 1, stage: "sighter")
    comp = (1..12).map { |n| create(:shot, card: c, number: n + 1, stage: "match", match_number: n, series: (n - 1) / 10 + 1) }
    delete shot_path(comp[2])   # match shot 3
    rows = match.shots.where(stage: "match").order(:match_number).pluck(:match_number, :series)
    expect(rows).to eq((1..11).map { [ it, (it - 1) / 10 + 1 ] })   # the old shot 11 is now 10, back in series 1
    expect(match.shots.where(stage: "sighter").pluck(:number)).to eq([ 1 ])

    final = create(:practice_session, user:, course: "final", status: "ended", ended_at: Time.current)
    fc = create(:card, practice_session: final, number: 1)
    fs = (1..6).map { |n| create(:shot, card: fc, number: n, stage: "match", match_number: n, series: n <= 5 ? 1 : 2) }
    delete shot_path(fs[0])
    expect(final.shots.order(:match_number).pluck(:match_number, :series)).to eq([ [ 1, 1 ], [ 2, 1 ], [ 3, 1 ], [ 4, 1 ], [ 5, 2 ] ])
  end

  it "updates a live range screen" do
    session.update!(ended_at: nil, status: "shooting")
    allow(LiveBroadcast).to receive(:new).and_call_original
    delete shot_path(shots.last)
    expect(LiveBroadcast).to have_received(:new).with(session)
  end

  it "won't delete another user's shot" do
    other = create(:shot, card: create(:card))
    delete shot_path(other)
    expect(response).to have_http_status(:not_found)
    expect(Shot.exists?(other.id)).to be(true)
  end
end
