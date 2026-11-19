require "rails_helper"

RSpec.describe PracticeSession, "plan link" do
  let(:session) { build(:practice_session) }

  it "is fine without a plan block, with a whole plan day, or with a shooting block" do
    expect(session).to be_valid
    expect(build(:practice_session, plan_week: 1, plan_day: 1)).to be_valid
    expect(build(:practice_session, plan_week: 1, plan_day: 1, plan_block: 2)).to be_valid
  end

  it "refuses a link to something that is not in the plan" do
    expect(build(:practice_session, plan_week: 13, plan_day: 1)).not_to be_valid
    expect(build(:practice_session, plan_week: 1)).not_to be_valid
    expect(build(:practice_session, plan_week: 1, plan_day: 1, plan_block: 1)).not_to be_valid   # the hold drill: no session of its own
    expect(build(:practice_session, plan_week: 1, plan_day: 1, plan_block: 9)).not_to be_valid
  end

  it "names the block and its reference" do
    linked = build(:practice_session, plan_week: 3, plan_day: 1, plan_block: 2)
    expect(linked.plan_ref).to eq("3-1-2")
    expect(linked.plan_found.block).to be_present
    expect(build(:practice_session).plan_found).to be_nil
    expect(build(:practice_session).plan_ref).to be_nil
  end
end
