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

  it "shows a day with its blocks, and the way into a session for an air pistol day" do
    enroll
    get plan_workout_path(1, 1)
    expect(response.body).to include("Hold drills", "Slow groups", "Start the session", "Pre-shot routine")
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

  describe "starting a session from a day" do
    let(:enrollment) { enroll }

    before do
      enrollment
      allow(CameraProbe).to receive(:run!)
    end

    it "links the session Start creates to that day and tags it" do
      post setup_path, params: { plan_day: "1-3" }
      started = create(:practice_session, user:)
      allow(EngineRunner).to receive(:start!).and_return(started)
      allow(RigCheck).to receive(:stop_for!)

      post practice_sessions_path, params: { practice_session: { target: "pistol", per_card: "10", camera: "0", mic: "none" } }

      expect(enrollment.workout_for(1, 3).practice_session).to eq(started)
      expect(started.reload.exercises.map(&:name)).to contain_exactly("Trigger control", "Follow-through")
    end

    it "forgets the day when the wizard is started from Practice instead" do
      post setup_path, params: { plan_day: "1-3" }
      post setup_path
      started = create(:practice_session, user:)
      allow(EngineRunner).to receive(:start!).and_return(started)
      allow(RigCheck).to receive(:stop_for!)

      post practice_sessions_path, params: { practice_session: { target: "pistol", per_card: "10", camera: "0", mic: "none" } }

      expect(enrollment.workouts).to be_empty
      expect(started.reload.exercises).to be_empty
    end

    it "ignores a plan day that is not in the plan" do
      post setup_path, params: { plan_day: "99-1" }
      started = create(:practice_session, user:)
      allow(EngineRunner).to receive(:start!).and_return(started)
      allow(RigCheck).to receive(:stop_for!)

      post practice_sessions_path, params: { practice_session: { target: "pistol", per_card: "10", camera: "0", mic: "none" } }
      expect(enrollment.workouts).to be_empty
    end
  end

  it "unlinks a deleted session from its day instead of failing" do
    session = create(:practice_session, user:, status: "ended", ended_at: Time.current)
    enroll.link_session!(session, week: 1, day: 1)
    delete practice_session_path(session)
    expect(PracticeSession.exists?(session.id)).to be(false)
    expect(user.plan_enrollment.workout_for(1, 1)).to be_present
  end
end
