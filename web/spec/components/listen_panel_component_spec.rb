require "rails_helper"
require "view_component/test_helpers"

# The sound check stays the same height however much it hears: verdict and Next
# first, then the last few sounds newest first, the rest folded away.
RSpec.describe ListenPanelComponent, type: :component do
  include ViewComponent::TestHelpers

  def state(count)
    sounds = (1..count).map { { "n" => it, "t" => it * 2.0, "over_db" => it == 3 ? 60.0 : 30.0, "len_ms" => 250, "would_trigger" => it == 3 } }
    RigCheck::LiveProcess::State.new(kind: :listen, label: "sound check", user_id: 1, pid: 0, started_at: Time.current, finished: false,
                                     data: { "mic" => "Razer Kiyo", "trigger_db" => 45.0, "trigger_ms" => 180.0, "sounds" => sounds })
  end

  it "shows the last five sounds newest first and folds away the rest" do
    render_inline(described_class.new(state: state(12), user: nil))
    shown = page.all("#listen_panel > table tbody tr").map { it.first("td").text }
    expect(shown).to eq(%w[ 12 11 10 9 8 ])
    expect(page).to have_css("details summary", text: "Show 7 earlier sounds")
    expect(page.all("details tbody tr", visible: :all).map { it.first("td", visible: :all).text(:all) }).to eq(%w[ 7 6 5 4 3 2 1 ])
  end

  it "puts the verdict and Next above the sounds" do
    render_inline(described_class.new(state: state(12), user: nil))
    html = rendered_content
    expect(html).to include("1 sound would trigger</strong> out of 12 heard so far")
    expect(html.index("Next: start")).to be < html.index("<table")
  end

  it "has nothing to fold away with five sounds or fewer" do
    render_inline(described_class.new(state: state(4), user: nil))
    expect(page).to have_no_css("details")
  end
end
