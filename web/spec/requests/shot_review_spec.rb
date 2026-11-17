require "rails_helper"

# Calling shots with "Save and next": only the shots worth a look are visited
# (the rules' flags, or the model reading a different ring), across cards,
# wherever the shooter started; finishing them accepts the rest as scored.
RSpec.describe "Reviewing a session's shots" do
  let(:user) { create(:user) }
  let(:session) { create(:practice_session, user:, status: "ended", ended_at: Time.current) }
  let(:card1) { create(:card, practice_session: session, number: 1) }
  let(:card2) { create(:card, practice_session: session, number: 2) }
  # 0 line call, 1 plain, 2 overlap, 3 plain, 4 model disagrees, 5 ring uncertain
  let!(:shots) do
    [ card1, card1, card1, card2, card2, card2 ].each_with_index.map do |card, i|
      create(:shot, card:, number: card == card1 ? i + 1 : i - 2,
                    fired_at: Time.zone.parse("2026-11-11 15:31") + (i * 30).seconds,
                    line_call: i == 0, overlap: i == 2, ambiguous: i == 5,
                    estimates: { "model" => { "ring" => i == 4 ? 9 : 10, "p_ring" => 0.6 } })
    end
  end

  before { sign_in(user) }

  def save_call(shot, ring: "9")
    patch shot_path(shot), params: { shot: { ring: } }
    response.location
  end

  it "starting in the middle, visits only flagged shots - later cards, then the ones before - then returns" do
    visited = [ shots[2] ]
    loop do
      location = save_call(visited.last)
      break if location == practice_session_url(session)

      visited << Shot.find(location[%r{/shots/(\d+)\z}, 1])
    end
    expect(visited.map(&:id)).to eq [ shots[2], shots[4], shots[5], shots[0] ].map(&:id)
  end

  it "finishing the flagged shots accepts the rest as scored, with no tap" do
    [ 0, 2, 4 ].each { save_call(shots[it]) }
    save_call(shots[5])
    expect(flash[:notice]).to include("2 unflagged shots accepted as scored")
    plain = [ shots[1], shots[3] ].map(&:reload)
    expect(plain).to all(be_called)
    expect(plain.map(&:call_ring)).to eq [ 10, 10 ]
    expect(plain.map(&:call_x_mm)).to eq [ nil, nil ]
    expect(shots[5].reload.call_ring).to eq 9
  end

  it "starting on an unflagged shot keeps its own call and goes to the next flagged one" do
    expect(save_call(shots[1], ring: "8")).to eq shot_url(shots[2])
    expect(shots[1].reload.call_ring).to eq 8
  end

  it "says where you are and where Save goes" do
    get shot_path(shots[2])
    expect(response.body).to include("Shot 3 of 6 this session", "3 other flagged shots still to call",
                                      "Save and go to card 2, shot 2", "Card 1, shot 2", "Card 2, shot 1 →")
  end

  it "says when the model reads a different ring, without saying which" do
    get shot_path(shots[4])
    expect(response.body).to include("the engine and the scoring model read different rings")
  end

  describe "a blind call" do
    let(:estimated) do
      shots[0].tap { it.update!(decimal_score: 9.4, ring: 9,
                                estimates: { "model" => { "ring" => 8 }, "centroid" => [ 0.1, 0.2 ],
                                             "closeup" => { "centre" => [ 0, 0 ], "px_per_mm" => 20, "size_px" => 400 } }) }
    end

    it "hides the score, the ring and how it was scored until called, and picks no ring" do
      get shot_path(estimated)
      expect(response.body).to include("A blind call", "Flagged: line call")
      expect(response.body).not_to include("Scored <strong", "How it was scored", "9.4")
      expect(response.body).not_to match(/type="radio"[^>]*checked/)
    end

    it "refuses a save with no ring, then reveals the engine and model after the call" do
      patch shot_path(estimated), params: { shot: { x_mm: "", y_mm: "" } }
      expect(flash[:alert]).to eq "Pick the ring you see first."
      expect(estimated.reload).not_to be_called

      save_call(estimated, ring: "8")
      expect(flash[:notice]).to include("You called 8; the engine scored 9.4 (ring 9), the model ring 8.")
      get shot_path(estimated)
      expect(response.body).to include("How it was scored", "Scored <strong")
    end

    it "draws no estimate circles on the close-ups" do
      expect(CloseupComponent.new(shot: estimated, estimates: false).marks).to eq []
      expect(CloseupComponent.new(shot: estimated).marks.map(&:first)).to include(:centroid, :scored)
    end

    it "is not blind for an unflagged shot" do
      get shot_path(shots[1])
      expect(response.body).to include("How it was scored")
      expect(response.body).not_to include("A blind call")
    end
  end

  it "once every shot has a call, steps on through the flagged ones and ends at the session" do
    shots.each { it.update!(called_at: Time.current, call_ring: 10) }
    expect(save_call(shots[2])).to eq shot_url(shots[4])
    expect(save_call(shots[5])).to eq practice_session_url(session)
  end
end
