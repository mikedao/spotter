require "rails_helper"

# Calling shot after shot with "Save and next": every shot of the session gets
# visited, across cards, wherever the shooter started.
RSpec.describe "Reviewing a session's shots" do
  let(:user) { create(:user) }
  let(:session) { create(:practice_session, user:, status: "ended", ended_at: Time.current) }
  let(:card1) { create(:card, practice_session: session, number: 1) }
  let(:card2) { create(:card, practice_session: session, number: 2) }
  let!(:shots) do
    [ card1, card1, card1, card2, card2 ].each_with_index.map do |card, i|
      create(:shot, card:, number: card == card1 ? i + 1 : i - 2,
                    fired_at: Time.zone.parse("2026-11-11 15:31") + (i * 30).seconds)
    end
  end

  before { sign_in(user) }

  def save_call(shot)
    patch shot_path(shot), params: { shot: { ring: "9" } }
    response.location
  end

  it "starting in the middle, visits every shot - later cards, then the ones before - then returns" do
    visited = [ shots[1] ]
    loop do
      location = save_call(visited.last)
      break if location == practice_session_url(session)

      visited << Shot.find(location[%r{/shots/(\d+)\z}, 1])
    end
    expect(visited.map(&:id)).to eq [ shots[1], shots[2], shots[3], shots[4], shots[0] ].map(&:id)
    expect(shots.map(&:reload)).to all(be_called)
  end

  it "says where you are and where Save goes" do
    get shot_path(shots[1])
    expect(response.body).to include("Shot 2 of 5 this session", "4 other shots still without a call",
                                      "Save and go to card 1, shot 3", "Card 1, shot 1", "Card 1, shot 3 →")
  end

  it "once every shot has a call, steps on in order and ends at the session" do
    shots.each { it.update!(called_at: Time.current, call_ring: 10) }
    expect(save_call(shots[3])).to eq shot_url(shots[4])
    expect(save_call(shots[4])).to eq practice_session_url(session)
  end
end
