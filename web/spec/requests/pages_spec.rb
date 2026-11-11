require "rails_helper"

RSpec.describe "Pages" do
  let(:session) { create(:practice_session) }
  let(:card) { create(:card, practice_session: session) }
  let!(:shot) do
    create(:shot, card:, x_mm: -20.5, y_mm: 2.8, ring: 8, decimal_score: 8.4, line_call: true,
                  estimates: { "closeup" => { "centre" => [ -20.5, 2.8 ], "px_per_mm" => 20, "size_px" => 480 } })
  end

  it "lists sessions" do
    get root_path
    expect(response.body).to include("10m Air Pistol")
  end

  it "shows the range screen with the target, latest shot and stats" do
    get practice_session_path(session)
    expect(response.body).to include("<svg", "Latest shot", "8.4", "Check by eye: line call")
  end

  it "shows a shot for review" do
    get shot_path(shot)
    expect(response.body).to include("Your call", "Flagged: line call")
  end

  it "records the shooter's call beside the proposal" do
    patch shot_path(shot), params: { shot: { ring: "9", x_mm: "-18.4", y_mm: "2.1", note: "touches the 9" } }
    shot.reload
    expect(shot).to have_attributes(call_ring: 9, call_x_mm: -18.4, call_note: "touches the 9", ring: 8)
    expect(shot.called_at).to be_present
  end
end
