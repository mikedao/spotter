require "rails_helper"

# The session diary: exercise tags to tap, and problems / fixes / learned.
RSpec.describe "Session diary" do
  let(:user) { create(:user) }
  let(:session) { create(:practice_session, user:, status: "ended", ended_at: Time.current) }

  before { sign_in(user) }

  def save(**fields) = patch(diary_practice_session_path(session), params: { practice_session: { exercise_ids: [ "" ], **fields } })

  it "saves the three boxes and a new exercise, kept as a tag for next time" do
    get practice_session_path(session)
    expect(response.body).to include("Diary", "What did you practice?")

    save(new_exercise: " Trigger  control ", problems: "Pulled low left", fixes: "Slower squeeze", learned: "Breathe out first")
    expect(response).to redirect_to(practice_session_path(session, anchor: "diary"))
    expect(session.reload).to have_attributes(problems: "Pulled low left", fixes: "Slower squeeze", learned: "Breathe out first")
    expect(session.exercises.map(&:name)).to eq([ "Trigger control" ])

    later = create(:practice_session, user:, status: "ended", ended_at: Time.current)
    get practice_session_path(later)
    expect(response.body).to include("Trigger control")
  end

  it "ticks and unticks tags, and reuses a tag typed again in other case" do
    holding = user.exercises.create!(name: "Holding")
    strings = user.exercises.create!(name: "5-shot strings")
    session.update!(exercises: [ holding ])

    save(exercise_ids: [ "", holding.id.to_s, strings.id.to_s ], new_exercise: "holding")
    expect(session.reload.exercises).to contain_exactly(holding, strings)
    expect(user.exercises.count).to eq(2)

    save(exercise_ids: [ "", strings.id.to_s ])
    expect(session.reload.exercises).to eq([ strings ])
  end

  it "forgets a tag no session uses any more" do
    drill = user.exercises.create!(name: "Dry fire")
    session.update!(exercises: [ drill ])
    save
    expect(user.exercises.reload).to be_empty
  end

  it "ignores another user's tag" do
    theirs = create(:user).exercises.create!(name: "Theirs")
    save(exercise_ids: [ "", theirs.id.to_s ])
    expect(session.reload.exercises).to be_empty
  end

  it "keeps the gun and pellets when the diary is saved" do
    gun = create(:gun, user:)
    session.update!(gun:)
    save(learned: "Something")
    expect(session.reload.gun).to eq(gun)
  end
end
