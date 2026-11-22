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
    expect(CGI.unescapeHTML(response.body)).to include("Today's training", "Routine and groups", "Week 1", "of 84 workouts done")
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

  it "offers one session on a dry-fire day: the live air pistol block after the Pardini is cased" do
    enroll
    get plan_workout_path(1, 2)
    body = CGI.unescapeHTML(response.body)
    expect(body).to include("Safety", "Dry-fire the Pardini only", "Case the Pardini first", "Start the session: Air pistol (FWB 65)")
    expect(body.scan("Start the session").size).to eq(1)
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
    expect(response.body).to include("0</strong> of 84")
  end

  it "makes a week's range day a match from the calendar, and back" do
    enroll
    get training_plan_path
    expect(response.body).to include("Make it a match")
    post plan_match_path(ref: "2-7", open: 2)
    expect(response).to redirect_to(training_plan_path(open: 2))
    follow_redirect!
    expect(CGI.unescapeHTML(response.body)).to include("a full 60 shots", "Match day", "Range day instead")
    get plan_workout_path(2, 7)
    expect(CGI.unescapeHTML(response.body)).to include("Match day", "Start the session: Match")
    delete plan_match_path(ref: "2-7")
    expect(user.plan_enrollment.reload.match_days).to be_empty
    post plan_match_path(ref: "2-3")
    follow_redirect!
    expect(response.body).to include("Only a range day can be made a match")
  end

  describe "swapping days" do
    before { enroll }

    it "swaps two days and keeps the week open" do
      patch swap_plan_days_path, params: { from: "1-1", to: "1-2", open: "1" }
      expect(response).to redirect_to(training_plan_path(open: "1"))
      expect(user.plan_enrollment.reload.order.first(2)).to eq(%w[1-2 1-1])
      get training_plan_path
      expect(response.body).to include('data-ref="1-2"')
    end

    it "says why a swap is refused" do
      patch swap_plan_days_path, params: { from: "2-1", to: "1-7" }
      follow_redirect!
      expect(CGI.unescapeHTML(response.body)).to include("two range days in week 2")
      expect(user.plan_enrollment.reload).not_to be_moved
    end

    it "makes a day a rest day, shows it, and takes it out" do
      post add_plan_rest_path, params: { ref: "1-2", open: "1" }
      expect(response).to redirect_to(training_plan_path(open: "1"))
      expect(user.plan_enrollment.reload.order.first(3)).to eq(%w[1-1 rest-1 1-2])
      get training_plan_path(open: "1")
      expect(response.body).to include('data-ref="rest-1"', "Rest day", "Week 13")

      delete remove_plan_rest_path, params: { ref: "rest-1" }
      expect(user.plan_enrollment.reload).not_to be_moved
    end

    it "shows an added rest day as today's training" do
      user.plan_enrollment.update!(started_on: Time.zone.today)
      post add_plan_rest_path, params: { ref: "1-1" }
      get training_plan_path
      expect(response.body).to include("You added this one")
    end

    it "puts the days back" do
      patch swap_plan_days_path, params: { from: "1-1", to: "1-2" }
      delete reset_plan_days_path
      expect(user.plan_enrollment.reload).not_to be_moved
    end

    it "does nothing for someone not on the plan" do
      user.plan_enrollment.destroy
      patch swap_plan_days_path, params: { from: "1-1", to: "1-2" }
      expect(response).to redirect_to(training_plan_path)
    end
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

    def start_form(**fields) = { practice_session: start[:practice_session].merge(fields) }

    it "starts the plan block when it is the choice: its course, its groups, linked and tagged" do
      post setup_path, params: { plan_block: "9-6-2" }   # Full match
      expect(EngineRunner).to receive(:start!).with(hash_including(course: "match")).and_return(started)
      post practice_sessions_path, params: start_form(mode: "plan", group_of: "0")
      expect(started.reload).to have_attributes(plan_week: 9, plan_day: 6, plan_block: 2)
      expect(started[:group_of]).to eq(0)   # whole card, chosen: the method then says nil

      post setup_path, params: { plan_block: "1-3-2" }   # Trigger groups: practice in 5-shot groups
      expect(EngineRunner).to receive(:start!).with(hash_including(course: nil, per_card: "10")).and_return(started)
      post practice_sessions_path, params: start_form(mode: "plan", per_card: "10", group_of: "5")
      expect(started.reload).to have_attributes(plan_day: 3, plan_block: 2, group_of: 5)
    end

    it "starts an ordinary session, not counted for the plan, when something else is picked" do
      post setup_path, params: { plan_block: "1-3-2" }
      expect(EngineRunner).to receive(:start!).with(hash_including(course: "final")).and_return(started)
      post practice_sessions_path, params: start_form(mode: "final", group_of: "0")
      expect(started.reload).to have_attributes(plan_week: nil)
      expect(started[:group_of]).to eq(0)
      expect(started.group_of).to be_nil
      expect(started.exercises).to be_empty
    end

    it "measures 5-shot groups in a session outside the plan when asked, and ignores a value it doesn't know" do
      post setup_path
      post practice_sessions_path, params: start_form(mode: "", group_of: "5")
      expect(started.reload.group_of).to eq(5)
      started.update!(group_of: nil)
      post practice_sessions_path, params: start_form(mode: "", group_of: "7")
      expect(started.reload.group_of).to be_nil
    end

    it "fills shots per card from the plan block" do
      user.update!(last_camera: "0", last_mic: "none")
      post setup_path, params: { plan_block: "12-2-2" }   # the lane in the taper: one card of 10
      get setup_start_path
      expect(TrainingPlan.find_block("12-2-2").block.shots).to eq(10)
      expect(response.body).to match(/name="practice_session\[per_card\]"[^>]*value="10"|value="10"[^>]*name="practice_session\[per_card\]"/)
      expect(response.body).to include('data-per-card="10"', 'data-action="start-choice#pick"')
    end

    it "preloads the Start step: the block's instructions, cards and tags" do
      post setup_path, params: { plan_block: "1-3-2" }
      user.update!(last_camera: "0", last_mic: "none")
      get setup_start_path
      body = CGI.unescapeHTML(response.body)
      expect(body).to include("From your training plan", "Trigger groups", "Week 1 · Day 3 · Trigger and follow-through",
                              "#{TrainingPlan.find_block('1-3-2').block.shots} shots", "2 cards of 10",
                              "5-shot groups measured live", "Counts for your plan and is tagged Trigger control and Follow-through")
      expect(body).to match(/value="plan"[^>]*checked|checked[^>]*value="plan"/)
      expect(body).to match(/value="5"[^>]*checked[^>]*name="practice_session\[group_of\]"|name="practice_session\[group_of\]"[^>]*value="5"[^>]*checked|checked="checked"[^>]*name="practice_session\[group_of\]"[^>]*value="5"/)
      expect(body).to match(/name="practice_session\[per_card\]"[^>]*value="10"|value="10"[^>]*name="practice_session\[per_card\]"/)
    end

    it "preloads a match for a match block" do
      post setup_path, params: { plan_block: "9-6-2" }
      user.update!(last_camera: "0", last_mic: "none")
      get setup_start_path
      body = CGI.unescapeHTML(response.body)
      expect(body).to include("From your training plan", "Full match", "60 shots", "6 cards of 10")
      expect(body).to match(/value="plan"[^>]*checked|checked[^>]*value="plan"/)
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
      expect(body).to include("Slow groups", "Week 1 · Day 1", "Cards of 10, measured in groups of 5")
      # The instructions sit in the bar itself, in view without opening it: a reminder while shooting.
      bar = Nokogiri::HTML(response.body).at_css("[data-plan-block] summary")
      expect(bar.at_css("[data-plan-instructions]").text).to start_with("5-shot groups. Same routine every shot")
    end

    it "shows nothing extra on a session that was not started from the plan" do
      get practice_session_path(started)
      expect(response.body).not_to include("data-plan-block")
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
