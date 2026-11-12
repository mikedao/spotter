require "rails_helper"

# Chatty mode's commentary: what it notices and what it says.
RSpec.describe Commentary do
  let(:user) { create(:user, chatty: true) }
  let(:session) { create(:practice_session, user:, started_at: 1.hour.ago) }
  let(:card) { create(:card, practice_session: session, number: 1) }

  # Shots in order: ring, and where (x, y mm) - default just right of center.
  def fire(*rings, at: [ 3.0, 0.0 ], **attrs)
    rings.map do |r|
      n = (card.shots.maximum(:number) || 0) + 1
      create(:shot, card:, number: n, ring: r, decimal_score: r + 0.3, x_mm: at[0], y_mm: at[1],
                    fired_at: session.started_at + n.minutes, **attrs)
    end.last
  end

  def comment_on(shot) = described_class.new(session.reload, random: Random.new(1)).after_shot(shot)
  def said(sentences) = sentences.map { it.join(", ") }.join(". ")

  it "counts a streak of tens" do
    fire(9, 10, 10)
    expect(comment_on(fire(10))).to be_present.and(satisfy { said(it).include?("3") })
  end

  it "notices five in a row in the nine or better" do
    fire(8, 9, 10, 9, 9)
    expect(said(comment_on(fire(9)))).to match(/5/)
  end

  it "notices three in a row on the same side, and suggests a fix" do
    fire(10, 8, 8, at: [ -9.0, -9.0 ])
    sentences = comment_on(fire(8, at: [ -9.0, -9.0 ]))
    expect(said(sentences)).to include("low left")
    expect(sentences.size).to eq(2)   # the pattern, then the advice
  end

  it "steadies after a bad shot, and says nothing after an ordinary one" do
    fire(9, at: [ 6.0, 2.0 ])
    fire(9, at: [ -2.0, 6.0 ])
    expect(Commentary.lines["bad_shot"]).to include(said(comment_on(fire(6, at: [ 0.0, -40.0 ]))))
    expect(comment_on(fire(9, at: [ -6.0, 2.0 ]))).to eq([])
  end

  it "sums up every 10 shots: the total and how it compares - no pace or goal talk" do
    fire(9, 9, 9, 9, 9, 9, 9, 9, 9, at: [ 6.0, 2.0 ])
    first = comment_on(fire(9, at: [ -6.0, 2.0 ]))
    expect(first.first.last).to eq("90")                                  # the card's total, said after the lead
    expect(said(first)).not_to include("565")
    expect(first.size).to eq(1)                                           # just the card and its total
    fire(10, 10, 9, 10, 10, 9, 10, 10, 9, at: [ 1.0, 1.0 ])
    second = comment_on(fire(10, at: [ 1.0, 1.0 ]))
    expect(second.first.last).to eq("97")
    expect(Commentary.lines["best_today"] + Commentary.lines["personal_best"]).to include(said(second).split(". ")[1])
  end

  it "says halfway and last series in a match, and sums the match up at the end" do
    session.update!(course: "match")
    50.times { |i| create(:shot, card:, number: i + 1, ring: 9, decimal_score: 9.4, x_mm: (i % 5) - 2.0, y_mm: 1.0,
                                 stage: "match", match_number: i + 1, fired_at: session.started_at + i.minutes) }
    c = described_class.new(session.reload, random: Random.new(2))
    thirty = card.shots.find_by(match_number: 30)
    expect(c.after_shot(thirty).flatten).to include("270")                # halfway: the total so far
    expect(said(c.after_shot(card.shots.find_by(match_number: 50)))).to match(/last|final series/)

    summary = c.after_match
    expect(summary.flatten).to include("450")                             # the final score
    expect(said(summary)).not_to include("565")                           # no goal talk
  end

  it "leaves sighters alone, and stays quiet with chatty mode off" do
    sighter = fire(10, 10, 10, 10, stage: "sighter")
    expect(comment_on(sighter)).to eq([])
    user.update!(chatty: false)
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
    Commentary.after_event(session, type: "shot", record: fire(10))
    expect(Turbo::StreamsChannel).not_to have_received(:broadcast_append_to)
  end

  it "plays its remark on the range screen after the shot, with no tone" do
    fire(10, 10)
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
    Commentary.after_event(session.reload, type: "shot", record: fire(10))
    expect(Turbo::StreamsChannel).to have_received(:broadcast_append_to)
      .with(session, target: "announcements", html: a_string_including("&quot;kind&quot;:&quot;chat&quot;"))
  end

  it "knows every piece it may say, numbers filled in, to render ahead" do
    pieces = Commentary.pieces(user)
    expect(pieces).to include("3 tens in a row", "10 tens in a row", "low left again", "96")
    expect(pieces.grep(/565|pace/)).to eq([])
    expect(pieces).to all(match(/\A[a-z0-9][a-z0-9 .,'-]*\z/))   # each one a valid voice piece
  end
end
