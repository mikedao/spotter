require "rails_helper"

# A finished session opens on the whole session, not its last card.
RSpec.describe "Finished session summary" do
  let(:user) { create(:user) }

  before { sign_in(user) }

  def card_of(session, number, rings, **attrs)
    card = create(:card, practice_session: session, number:)
    rings.each_with_index { |r, i| create(:shot, card:, number: i + 1, ring: r, decimal_score: r + 0.5, x_mm: i.to_f, y_mm: 1.0, **attrs) }
    card
  end

  it "numbers every shot on one target in firing order, across cards" do
    session = create(:practice_session, user:, status: "ended", ended_at: Time.current)
    card_of(session, 1, [ 9, 9 ])
    card_of(session, 2, [ 10, 8 ])
    get practice_session_path(session)
    labels = Nokogiri::HTML(response.body).css("#session_target svg text").map(&:text).grep(/\A\d+\z/) - %w[ 7 8 ]
    expect(labels.sort_by(&:to_i)).to include("1", "2", "3", "4")
    expect(response.body).to include("Session result", "All 4 shots", "36")
  end

  it "shows a match's result: total of 60, series with the worst marked, sighters and zeros" do
    session = create(:practice_session, user:, course: "match", status: "ended", ended_at: Time.current)
    c = create(:card, practice_session: session, number: 1)
    create(:shot, card: c, number: 1, stage: "sighter", ring: 7)
    12.times do |i|
      create(:shot, card: c, number: i + 2, stage: "match", match_number: i + 1, series: i / 10 + 1,
                    ring: i == 11 ? 5 : 9, x_mm: 1.0 + i, y_mm: 0, penalty: (i == 10 ? "out of time" : nil))
    end
    get practice_session_path(session)
    body = response.body
    expect(body).to include("Match result", "of 60 shots", "1 sighter (not counted)", "1 shot out of time, scored zero")
    expect(body).to include("95")   # 10 x 9 + 0 + 5 = 95, whole rings
    series = Nokogiri::HTML(body).css("ol[aria-label='Series totals'] li").map { it.text.squish }
    expect(series).to eq([ "S1 90", "S2 5" ])
    expect(body).not_to include("Shots on this card")   # not the live screen
  end
end
