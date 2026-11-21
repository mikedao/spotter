require "rails_helper"
require "view_component/test_helpers"

# A plan block shot in 5-shot groups without changing the card: the range screen
# measures the group being shot, live, and keeps the card's earlier groups.
RSpec.describe "Live 5-shot groups on one card", type: :component do
  include ViewComponent::TestHelpers

  let(:user) { create(:user) }
  let(:session) do
    user.create_plan_enrollment!(started_on: Time.zone.today)
    create(:practice_session, user:, plan_week: 1, plan_day: 1, plan_block: 2)   # "Slow groups": groups of 5
  end
  let(:card) { create(:card, practice_session: session, number: 1) }

  # Group 1 spread 20 mm wide (x -10..10); group 2 so far 3 shots, 6 mm wide.
  before do
    [ [ -10, 0 ], [ 10, 0 ], [ 0, 5 ], [ 0, -5 ], [ 2, 2 ], [ 20, 20 ], [ 26, 20 ], [ 23, 22 ] ].each_with_index do |(x, y), i|
      create(:shot, card:, number: i + 1, x_mm: x, y_mm: y, fired_at: Time.current + i * 30)
    end
  end

  it "knows the session measures groups of 5, and splits the card in runs" do
    expect(session.group_of).to eq(5)
    groups = card.stats.groups(of: 5)
    expect(groups.map(&:size_mm)).to eq([ 20.0, 6.0 ])
    expect(groups.map(&:complete)).to eq([ true, false ])
    expect(groups.last.range_text).to eq("shots 6–8")
  end

  def render_section(section) = render_inline(LivePanelComponent.new(session: session.reload, section:))

  it "draws the current group on the target with its widest pair, earlier groups faded" do
    render_section(:target)
    expect(page).to have_css("g[data-group-size='6.0'] line")
    expect(page).to have_css("circle[data-faded]", count: 5)
    expect(page).to have_text("Group 2: 6.0 mm (2 to go)")
  end

  it "lists each group's shots and size beside the latest shot, the current one marked" do
    render_section(:latest)
    expect(page).to have_css("li[data-group='1']", text: "20.0 mm")
    expect(page).to have_css("li[data-group='2'][aria-current]", text: "6.0 mm")
    expect(page).to have_css("li[data-group='2']", text: "2 to go")
  end

  it "gives every group's size in the card's numbers" do
    render_section(:stats)
    expect(page).to have_text("Groups of 5")
    expect(page).to have_text("20.0 · 6.0 mm")
  end

  it "keeps the plain card view for a session not shot in groups" do
    session.update!(plan_week: nil, plan_day: nil, plan_block: nil)
    render_section(:target)
    expect(page).to have_no_css("circle[data-faded]")
    render_section(:stats)
    expect(page).to have_text("Group")
    expect(page).to have_no_text("Groups of")
  end
end
