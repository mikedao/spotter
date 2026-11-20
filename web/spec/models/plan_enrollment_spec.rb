require "rails_helper"

RSpec.describe PlanEnrollment do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:start) { Date.new(2026, 11, 2) }
  let(:enrollment) { user.create_plan_enrollment!(started_on: start) }

  it "works out the plan day from the start date, a week being seven days" do
    expect(enrollment.position(start)).to eq([ 1, 1 ])
    expect(enrollment.position(start + 6)).to eq([ 1, 7 ])
    expect(enrollment.position(start + 7)).to eq([ 2, 1 ])
    expect(enrollment.position(start + 83)).to eq([ 12, 7 ])
    expect(enrollment.position(start - 1)).to be_nil
    expect(enrollment.position(start + 84)).to be_nil
    expect(enrollment.scheduled_on(2, 1)).to eq(start + 7)
  end

  it "counts finished workouts, not rest days, and lists missed ones" do
    travel_to Time.zone.local(2026, 11, 5, 9) do
      enrollment.workouts.create!(week: 1, day: 1, completed_at: Time.current)
      enrollment.workouts.create!(week: 1, day: 7, completed_at: Time.current)   # a rest day
      enrollment.workouts.create!(week: 1, day: 2)                                # started, not finished
      expect(enrollment.done_count).to eq(1)
      expect(enrollment.workout_count).to eq(72)
      expect(enrollment.missed.map(&:ref)).to eq([ "1-2", "1-3" ])   # days 1-3 are past; day 4 is today
    end
  end

  it "knows when it has not started and when it is over" do
    travel_to Time.zone.local(2026, 11, 1, 9) do
      expect(enrollment.today).to be_nil
      expect(enrollment.starts_in).to eq(1)
    end
    travel_to Time.zone.local(2027, 2, 1, 9) do
      expect(enrollment).to be_finished
    end
  end

  it "refuses a start date far in the future" do
    expect(user.build_plan_enrollment(started_on: Time.zone.today + 60)).not_to be_valid
  end

  describe "swapping days" do
    it "trades two days' places on the calendar, and keeps what is about each day" do
      enrollment.workouts.create!(week: 1, day: 1, completed_at: Time.current)
      enrollment.swap!("1-1", "1-3")

      expect(enrollment.reload.position(start)).to eq([ 1, 3 ])
      expect(enrollment.position(start + 2)).to eq([ 1, 1 ])
      expect(enrollment.scheduled_on(1, 1)).to eq(start + 2)
      expect(enrollment.done?(1, 1)).to be true
      expect(enrollment.calendar.first.map(&:ref).first(3)).to eq(%w[1-3 1-2 1-1])
      expect(enrollment).to be_moved
    end

    it "can move a day into another week, and back" do
      enrollment.swap!("1-1", "2-1")
      expect(enrollment.scheduled_on(1, 1)).to eq(start + 7)
      expect(enrollment.calendar[1].first.ref).to eq("1-1")
      enrollment.swap!("1-1", "2-1")
      expect(enrollment).not_to be_moved
      expect(enrollment.schedule).to be_nil
    end

    it "keeps one range day a week" do
      expect(TrainingPlan.day(1, 7)).to be_range
      expect { enrollment.swap!("2-1", "1-7") }.to raise_error(described_class::Refused, /two range days in week 2/)
      expect(enrollment.reload).not_to be_moved

      enrollment.swap!("1-7", "2-7")   # a range day for a range day is fine
      expect(enrollment.calendar[0].last.ref).to eq("2-7")
    end

    it "refuses what is not a day of the plan, and puts the order back on request" do
      expect { enrollment.swap!("1-1", "99-1") }.to raise_error(described_class::Refused)
      enrollment.swap!("1-1", "1-2")
      enrollment.reset_schedule!
      expect(enrollment).not_to be_moved
    end

    it "ignores a damaged saved order" do
      enrollment.update!(schedule: '["1-1"]')
      expect(enrollment.order).to eq(enrollment.natural_order)
    end
  end

  describe "rest days" do
    it "makes a day a rest day and pushes it and everything after it a day later" do
      enrollment.workouts.create!(week: 1, day: 2, completed_at: Time.current)
      enrollment.add_rest!("1-2")

      expect(enrollment.reload.order.first(3)).to eq(%w[1-1 rest-1 1-2])
      expect(enrollment.order.size).to eq(85)
      expect(enrollment.scheduled_on(1, 2)).to eq(start + 2)
      expect(enrollment.done?(1, 2)).to be true
      expect(enrollment.calendar.size).to eq(13)
      expect(enrollment.calendar.first[1]).to be_pause
      expect(enrollment.position(start + 1)).to be_nil
    end

    it "knows today is an added rest day, and when the longer plan is over" do
      enrollment.add_rest!("1-1")
      travel_to Time.zone.local(2026, 11, 2, 9) do
        expect(enrollment).to be_rest_today
        expect(enrollment.today).to be_nil
      end
      travel_to Time.zone.local(2026, 11, 3, 9) { expect(enrollment.today.ref).to eq("1-1") }
      travel_to start + 84 do
        expect(enrollment.reload).not_to be_finished
        expect(enrollment.today.ref).to eq("12-7")
      end
      travel_to start + 85 do
        expect(enrollment).to be_finished
      end
    end

    it "takes a rest day out again, and swaps with one" do
      enrollment.add_rest!("1-2")
      enrollment.add_rest!("1-1")
      expect(enrollment.order.first(4)).to eq(%w[rest-2 1-1 rest-1 1-2])

      enrollment.remove_rest!("rest-2")
      enrollment.swap!("rest-1", "1-3")
      expect(enrollment.order.first(4)).to eq(%w[1-1 1-3 1-2 rest-1])
      enrollment.remove_rest!("rest-1")
      expect(enrollment.order.first(3)).to eq(%w[1-1 1-3 1-2])
      expect { enrollment.remove_rest!("1-1") }.to raise_error(described_class::Refused)
      expect { enrollment.add_rest!("99-1") }.to raise_error(described_class::Refused)
    end

    it "goes back to the plan's order with no rest days when reset" do
      enrollment.add_rest!("1-1")
      enrollment.reset_schedule!
      expect(enrollment.order.size).to eq(84)
    end
  end

  describe "#link_session!" do
    it "ties the session to the block and tags it, reusing tags typed in another case" do
      user.exercises.create!(name: "rhythm")
      session = create(:practice_session, user:)

      enrollment.link_session!(session, week: 1, day: 1, block: 3)   # Steady-pace series

      expect(session.reload).to have_attributes(plan_week: 1, plan_day: 1, plan_block: 3)
      expect(session.plan_found.block.name).to eq("Steady-pace series")
      expect(session.exercises.map(&:name)).to eq([ "rhythm" ])
      expect(user.exercises.count).to eq(1)
    end

    it "keeps a session's own tags and adds the block's" do
      own = user.exercises.create!(name: "Something else")
      session = create(:practice_session, user:, exercises: [ own ])

      enrollment.link_session!(session, week: 1, day: 3, block: 2)   # Trigger groups

      expect(session.reload.exercises.map(&:name)).to contain_exactly("Something else", "Trigger control", "Follow-through")
    end

    it "leaves a session alone for a block that has no session of its own" do
      session = create(:practice_session, user:)
      enrollment.link_session!(session, week: 1, day: 1, block: 1)   # Hold drills: the timer
      expect(session.reload.plan_week).to be_nil
    end

    it "can give one day several sessions, one per block" do
      first = create(:practice_session, user:)
      second = create(:practice_session, user:)
      enrollment.link_session!(first, week: 1, day: 1, block: 2)
      enrollment.link_session!(second, week: 1, day: 1, block: 3)
      expect(user.practice_sessions.for_plan_day(1, 1).map(&:plan_block)).to contain_exactly(2, 3)
    end
  end

  it "does not link another user's session" do
    stranger = create(:practice_session)
    expect { enrollment.link_session!(stranger, week: 1, day: 1, block: 2) }.to raise_error(ArgumentError)
  end
end
