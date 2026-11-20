require "rails_helper"

RSpec.describe "Training plan" do
  let(:user) { create(:user) }

  before { sign_in(user) }

  def enroll(on: Time.zone.today) = user.create_plan_enrollment!(started_on: on)

  it "offers to start the plan, then starts it" do
    get training_plan_path
    expect(response.body).to include("Start the plan", "Foundation", "Consistency", "Pressure")

    post training_plan_path, params: { started_on: "2026-11-02" }
    expect(user.reload.plan_enrollment.started_on).to eq(Date.new(2026, 11, 2))
    expect(response).to redirect_to(training_plan_path)
  end

  it "starts today when the date is missing or nonsense" do
    post training_plan_path, params: { started_on: "soon" }
    expect(user.reload.plan_enrollment.started_on).to eq(Time.zone.today)
  end

  it "shows today's workout on the plan page and on Practice" do
    enroll
    get training_plan_path
    expect(CGI.unescapeHTML(response.body)).to include("Today's training", "Routine and groups", "Week 1", "of 72 workouts done")
    get practice_sessions_path
    expect(CGI.unescapeHTML(response.body)).to include("Today's training", "Routine and groups")
  end

  it "says when the plan is a few days away" do
    enroll(on: Time.zone.today + 3)
    get training_plan_path
    expect(response.body).to include("in 3 days")
  end

  it "shows a day with its blocks, and a way into a session for each shooting block" do
    enroll
    get plan_workout_path(1, 1)
    body = CGI.unescapeHTML(response.body)
    expect(body).to include("Hold drills", "Slow groups", "Steady-pace series")
    expect(body).to include("Start the session: Slow groups", "Start the session: Steady-pace series")
    expect(body).to include('value="1-1-2"', 'value="1-1-3"')   # each starts its own block
  end

  it "does not offer a session for a dry-fire day" do
    enroll
    get plan_workout_path(1, 2)
    expect(response.body).to include("Safety", "Dry-fire the Pardini only")
    expect(response.body).not_to include("Start the session")
  end

  it "404s a day that is not in the plan, and sends someone without a plan to the overview" do
    get plan_workout_path(1, 1)
    expect(response).to redirect_to(training_plan_path)

    enroll
    get plan_workout_path(13, 1)
    expect(response).to have_http_status(:not_found)
  end

  it "ticks a day off with a note, and unticks it" do
    enroll
    patch plan_workout_path(1, 1), params: { done: "1", note: "  held well  " }
    workout = user.plan_enrollment.workout_for(1, 1)
    expect(workout).to be_done
    expect(workout.note).to eq("held well")

    get plan_workout_path(1, 1)
    expect(response.body).to include("Not done after all", "held well")

    patch plan_workout_path(1, 1), params: { done: "0" }
    expect(workout.reload).not_to be_done
  end

  it "leaves the plan, forgetting the ticks" do
    enroll.workouts.create!(week: 1, day: 1, completed_at: Time.current)
    delete training_plan_path
    expect(user.reload.plan_enrollment).to be_nil
    expect(PlanWorkout.count).to eq(0)
  end

  it "keeps each user's plan to themselves" do
    other = create(:user)
    other.create_plan_enrollment!(started_on: Time.zone.today).workouts.create!(week: 1, day: 1, completed_at: Time.current)
    enroll
    get training_plan_path
    expect(response.body).to include("0</strong> of 72")
  end

  describe "starting a session from a block" do
    let(:enrollment) { enroll }
    let(:started) { create(:practice_session, user:) }
    let(:start) { { practice_session: { target: "pistol", per_card: "5", camera: "0", mic: "none" } } }

    before do
      enrollment
      allow(CameraProbe).to receive(:run!)
      allow(EngineRunner).to receive(:start!).and_return(started)
      allow(RigCheck).to receive(:stop_for!)
    end

    it "links the session Start creates to that block and tags it" do
      post setup_path, params: { plan_block: "1-3-2" }   # Trigger groups
      post practice_sessions_path, params: start

      expect(started.reload).to have_attributes(plan_week: 1, plan_day: 3, plan_block: 2)
      expect(started.exercises.map(&:name)).to contain_exactly("Trigger control", "Follow-through")
    end

    it "preloads the Start step: the block's instructions, cards and tags" do
      post setup_path, params: { plan_block: "1-3-2" }
      user.update!(last_camera: "0", last_mic: "none")
      get setup_start_path
      body = CGI.unescapeHTML(response.body)
      expect(body).to include("From your plan", "Week 1 · Day 3 · Trigger groups", "#{TrainingPlan.find_block('1-3-2').block.shots} shots")
      expect(body).to include("10 shots a card", "Trigger control and Follow-through")
      expect(body).to match(/name="practice_session\[per_card\]"[^>]*value="10"|value="10"[^>]*name="practice_session\[per_card\]"/)
    end

    it "preloads a match for a match block" do
      post setup_path, params: { plan_block: "9-6-2" }
      user.update!(last_camera: "0", last_mic: "none")
      get setup_start_path
      expect(response.body).to match(/value="match" checked|checked="checked"[^>]*value="match"|value="match"[^>]*checked/)
      expect(CGI.unescapeHTML(response.body)).to include("a match, 10 shots a card")
    end

    it "forgets the block when the wizard is started from Practice instead" do
      post setup_path, params: { plan_block: "1-3-2" }
      post setup_path
      post practice_sessions_path, params: start
      expect(started.reload.plan_week).to be_nil
      expect(started.exercises).to be_empty
    end

    it "ignores a block that is not in the plan, or has no session of its own" do
      [ "99-1-1", "1-1-1", "1-1" ].each do |ref|
        post setup_path, params: { plan_block: ref }
        post practice_sessions_path, params: start
        expect(started.reload.plan_week).to be_nil
      end
    end

    it "ticks a block once a session shot all of its shots" do
      enrollment.link_session!(started, week: 1, day: 1, block: 2)
      card = create(:card, practice_session: started)
      needed = TrainingPlan.find_block("1-1-2").block.shots
      (needed - 1).times { |i| create(:shot, card:, number: i + 1, ring: 9, decimal_score: 9.4) }
      get plan_workout_path(1, 1)
      expect(response.body).not_to include("✓ done")

      create(:shot, card:, number: needed, ring: 9, decimal_score: 9.4)
      get plan_workout_path(1, 1)
      expect(response.body).to include("✓ done")
    end

    it "lists the sessions shot for a block on the day, and offers another" do
      get plan_workout_path(1, 1)
      expect(CGI.unescapeHTML(response.body)).to include("Start the session: Slow groups")

      enrollment.link_session!(started, week: 1, day: 1, block: 2)
      get plan_workout_path(1, 1)
      body = CGI.unescapeHTML(response.body)
      expect(body).to include("Another session: Slow groups", "Start the session: Steady-pace series", practice_session_path(started))
    end

    it "shows the plan block on the session's own page" do
      enrollment.link_session!(started, week: 1, day: 1, block: 2)
      get practice_session_path(started)
      body = CGI.unescapeHTML(response.body)
      expect(body).to include("Week 1 · Day 1 · Slow groups", "5-shot groups. Same routine every shot", "Cards of 10, measured in groups of 5")
    end

    it "shows nothing extra on a session that was not started from the plan" do
      get practice_session_path(started)
      expect(response.body).not_to include("instructions ▾")
    end
  end

  it "keeps the day's note when a session shot for it is deleted" do
    session = create(:practice_session, user:, status: "ended", ended_at: Time.current)
    enroll.link_session!(session, week: 1, day: 1, block: 2)
    user.plan_enrollment.workouts.create!(week: 1, day: 1, note: "good day")
    delete practice_session_path(session)
    expect(PracticeSession.exists?(session.id)).to be(false)
    expect(user.plan_enrollment.workout_for(1, 1).note).to eq("good day")
  end
end
