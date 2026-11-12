require "rails_helper"

# Scoring a capture the engine couldn't: tap the hole on its picture.
RSpec.describe "Scoring a capture by hand" do
  let(:user) { create(:user) }
  let(:session) { create(:practice_session, user:, status: "ended", ended_at: Time.current, started_at: 1.hour.ago) }
  let(:card) { create(:card, practice_session: session, number: 1) }

  before { sign_in(user) }

  def scored(n, at) = create(:shot, card:, number: n, ring: 9, decimal_score: 9.3, x_mm: 5.0, y_mm: 1.0, fired_at: at)

  def capture(at)
    create(:shot, card:, number: nil, status: "unscored", unscored_reason: "no new hole on the card", fired_at: at,
                  x_mm: nil, y_mm: nil, ring: nil, decimal_score: nil).tap do |s|
      s.after_image.attach(io: StringIO.new("PNG"), filename: "after.png", content_type: "image/png")
      s.before_image.attach(io: StringIO.new("PNG"), filename: "before.png", content_type: "image/png")
    end
  end

  def with_engine
    ENV["SPOTTER_PYTHON"] = file_fixture("fake_pinpoint.sh").expand_path.to_s
    yield
  ensure
    ENV.delete("SPOTTER_PYTHON")
  end

  it "offers to score it on the capture's page, then scores it in its place in the order" do
    t = session.started_at
    first, second = scored(1, t + 1.minute), scored(2, t + 3.minutes)
    shot = capture(t + 2.minutes)

    get shot_path(shot)
    expect(response.body).to include("Tap the new hole on the picture", "Score this hole")

    with_engine { post pinpoint_shot_path(shot), params: { px: "912.5", py: "405.0" } }
    expect(response).to redirect_to(shot_path(shot))
    shot.reload
    expect(shot).to be_scored
    expect(shot).to be_pinpointed
    expect([ shot.x_mm, shot.y_mm, shot.ring ]).to eq([ -9.0, 3.0, 9 ])   # 9.5 mm out with the pellet rule: a 9
    expect(shot.closeup_after).to be_attached
    expect([ first.reload.number, shot.number, second.reload.number ]).to eq([ 1, 2, 3 ])   # in firing order

    get practice_session_card_path(session, 1)
    expect(response.body).to include("scored by you")
    get shot_path(shot)
    expect(response.body).to include("Placed by", "you, by hand (no new hole on the card)")
  end

  it "joins a match as the next competition shot, renumbering the ones after it" do
    session.update!(course: "match")
    t = session.started_at
    create(:shot, card:, number: 1, stage: "match", match_number: 1, series: 1, fired_at: t + 1.minute)
    later = create(:shot, card:, number: 2, stage: "match", match_number: 2, series: 1, fired_at: t + 3.minutes)
    shot = capture(t + 2.minutes)
    with_engine { post pinpoint_shot_path(shot), params: { px: "1", py: "1" } }
    expect(shot.reload).to have_attributes(stage: "match", match_number: 2, series: 1)
    expect(later.reload.match_number).to eq(3)
  end

  it "says so when the engine can't find the target in the picture" do
    shot = capture(session.started_at + 1.minute)
    allow(ShotPinpoint).to receive(:new).and_return(instance_double(ShotPinpoint, call: nil).tap { |d|
      allow(d).to receive(:call).and_raise(ShotPinpoint::Failed, "could not locate the target in the picture") })
    post pinpoint_shot_path(shot), params: { px: "1", py: "1" }
    expect(flash[:alert]).to include("could not locate the target")
    expect(shot.reload).not_to be_scored
  end
end
