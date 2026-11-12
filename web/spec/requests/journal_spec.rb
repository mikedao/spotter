require "rails_helper"

# The journal page: trends against the goal, filters, the goal setting.
RSpec.describe "Journal" do
  let(:user) { create(:user) }

  before { sign_in(user) }

  def session_with(rings, at:, **attrs)
    create(:practice_session, user:, started_at: at, status: "ended", ended_at: at + 1.hour, **attrs).tap do |s|
      card = create(:card, practice_session: s)
      rings.each_with_index { |r, i| create(:shot, card:, ring: r, decimal_score: r + 0.3, fired_at: at + i.minutes) }
    end
  end

  it "says what it needs before there is anything to chart" do
    get journal_path
    expect(response.body).to include("Nothing to show yet", "at least 10 shots")
  end

  it "charts score per 60 against the 565 goal and lists the sessions" do
    session_with([ 9 ] * 20, at: 3.days.ago)                    # 540
    session_with([ 10, 9 ] * 10, at: 1.day.ago, course: "match")   # 570
    get journal_path
    expect(response.body).to include("Score per 60 shots", "Goal 565", "10-shot series", "565 pace", "94.2")
    expect(response.body).to include("540", "570", "90 90", "95 95")
    expect(response.body).to include("10 to go", "to 565")   # recent pace 555; nothing earlier to compare with
    expect(response.body).to include("Personal best", "after 6 more sessions")
  end

  it "filters by kind, gun and exercise" do
    gun = create(:gun, user:, name: "LP10")
    drill = user.exercises.create!(name: "Holding")
    practice = session_with([ 8 ] * 10, at: 2.days.ago, gun:)
    practice.update!(exercises: [ drill ])
    session_with([ 10 ] * 10, at: 1.day.ago, course: "match")

    per_60 = -> { Nokogiri::HTML(response.body).css("tbody tr td:nth-child(3)").map(&:text) }
    get journal_path(kind: "match")
    expect(per_60.()).to eq(%w[ 600 ])
    get journal_path(gun: gun.id)
    expect(per_60.()).to eq(%w[ 480 ])
    get journal_path(exercise: drill.id)
    expect(per_60.()).to eq(%w[ 480 ])
    expect(response.body).to include("Holding")
  end

  it "sets and removes the goal line, and refuses nonsense" do
    session_with([ 9 ] * 10, at: 1.day.ago)
    patch journal_path, params: { target: "pistol", goal: "575" }
    expect(user.reload.goals).to eq("pistol" => 575)
    get journal_path
    expect(response.body).to include("Goal 575")

    patch journal_path, params: { target: "pistol", goal: "hello" }
    expect(flash[:alert]).to include("out of 600")
    patch journal_path, params: { target: "pistol", goal: "" }
    get journal_path
    expect(response.body).not_to include("Goal 5")
  end

  it "lists problems, fixes and lessons across sessions" do
    session_with([ 9 ] * 10, at: 1.day.ago, problems: "Flinched on the last series", learned: "Breathe out first")
    get journal_path
    expect(response.body).to include("Problems, fixes and lessons", "Flinched on the last series", "Breathe out first")
  end

  it "shows only the user's own sessions" do
    other = create(:user)
    create(:practice_session, user: other).then { |s| create(:card, practice_session: s).then { |c| 10.times { create(:shot, card: c, ring: 3) } } }
    get journal_path
    expect(response.body).to include("Nothing to show yet")
  end
end
