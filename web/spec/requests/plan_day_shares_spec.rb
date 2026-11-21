require "rails_helper"

RSpec.describe "Posting a training-plan day to CompetitiveShooter.org" do
  include ActiveJob::TestHelper

  let(:key) { "csk_#{"a1" * 16}" }
  let(:user) { create(:user, cso_api_key: key) }
  let(:posted) { { "id" => "p9", "url" => "https://competitiveshooter.org/posts/p9" } }

  before do
    sign_in(user)
    user.create_plan_enrollment!(started_on: Time.zone.today)
    # Week 1 day 2: hold drills, slow dry fire, a timed sequence (all dry fire).
    user.hold_drills.create!(reps: 10, hold_seconds: 8, rest_seconds: 10, reps_done: 10, held_seconds: 80, plan_week: 1, plan_day: 2, performed_at: Time.current)
    user.slow_drills.create!(shots: 25, string_size: 10, limit_seconds: 12, between_seconds: 10, string_rest_seconds: 60,
                             shots_fired: 25, let_downs: 1, break_seconds: 156.4, plan_week: 1, plan_day: 2, performed_at: Time.current)
    user.timed_drills.create!(strings: 4, shots: 5, string_seconds: 20, rest_seconds: 30, strings_done: 4, plan_week: 1, plan_day: 2, performed_at: Time.current)
    allow_any_instance_of(SharePicture).to receive(:jpeg).and_return("jpeg".b)
  end

  def client
    @client ||= instance_double(CompetitiveShooter).tap { allow(CompetitiveShooter).to receive(:new).with(key).and_return(it) }
  end

  it "previews the caption and the day's picture" do
    get plan_day_share_path(1, 2)
    body = CGI.unescapeHTML(response.body)
    expect(body).to include("Training plan, week 1 day 2: Hold and trigger (Pardini)", "✓ Hold drills: 10 of 10 holds of 8 s",
                            "✓ Slow dry fire: 25 of 25 slow shots in 12 s, 1 let down", "✓ Timed sequence: 4 of 4 strings of 5 in 20 s",
                            "Bullseye / Precision Pistol", "goes out by itself")
    expect(body).to include(plan_day_share_picture_path(1, 2, "day"))
  end

  it "draws the day's picture with each block's numbers" do
    svg = PlanDayShare.new(user, 1, 2).picture("day").svg
    doc = Nokogiri::XML(svg) { it.strict }
    expect(doc.text).to include("Hold and trigger (Pardini)", "10/10", "25/25", "4/4", "96% first time", "Logged with Spotter")
  end

  it "posts the day by itself when it is ticked done, once" do
    expect(client).to receive(:post!).once do |body:, topics:, images:|
      expect(body).to include("week 1 day 2", "Felt steady")
      expect(topics).to eq(%w[ bullseye-precision-pistol international-issf-pistol ])
      expect(images.map(&:first)).to eq([ "spotter-plan-day.jpg" ])
      posted
    end

    perform_enqueued_jobs do
      patch plan_workout_path(1, 2), params: { done: "1", note: "Felt steady" }
    end
    expect(flash[:notice]).to include("Posting it to CompetitiveShooter.org")
    expect(user.shared_posts.sole).to have_attributes(post_id: "p9", plan_week: 1, plan_day: 2, pictures: [ "day" ])

    perform_enqueued_jobs do
      patch plan_workout_path(1, 2), params: { done: "0" }
      patch plan_workout_path(1, 2), params: { done: "1" }
    end
    expect(user.shared_posts.count).to eq(1)

    get plan_workout_path(1, 2)
    expect(response.body).to include("Posted to CompetitiveShooter.org", posted["url"])
  end

  it "posts nothing without a key" do
    user.update!(cso_api_key: nil)
    expect(CompetitiveShooter).not_to receive(:new)
    perform_enqueued_jobs { patch plan_workout_path(1, 2), params: { done: "1" } }
    expect(flash[:notice]).to eq("Done. Nice work.")
  end

  it "keeps a failed post's reason on the day and posts it by hand" do
    allow(client).to receive(:post!).and_raise(CompetitiveShooter::Error, "That's CompetitiveShooter.org's limit of 10 posts an hour.")
    perform_enqueued_jobs { patch plan_workout_path(1, 2), params: { done: "1" } }
    expect(user.plan_enrollment.workout_for(1, 2).share_error).to include("limit of 10 posts")
    get plan_workout_path(1, 2)
    expect(CGI.unescapeHTML(response.body)).to include("didn't go out", "limit of 10 posts", "Look and post it")

    allow(client).to receive(:post!).and_return(posted)
    post plan_day_share_path(1, 2)
    expect(response).to redirect_to(plan_workout_path(1, 2))
    expect(user.shared_posts.sole.plan_day).to eq(2)
    expect(PlanWorkout.find_by!(week: 1, day: 2).share_error).to be_nil
  end

  it "adds the sessions' target and numbers when air pistol was shot for the day" do
    session = create(:practice_session, user:, status: "ended", ended_at: Time.current, plan_week: 1, plan_day: 1, plan_block: 2)
    card = create(:card, practice_session: session, number: 1)
    5.times { |i| create(:shot, card:, number: i + 1, ring: 9, decimal_score: 9.3, x_mm: i * 2.0, y_mm: 1.0) }
    share = PlanDayShare.new(user, 1, 1)
    expect(share.picture_kinds).to eq(%w[ day hero stats ])
    expect(share.topics).to eq([ "international-issf-pistol" ])
  end

  it "serves the day's picture as a JPEG", if: system("which rsvg-convert > /dev/null 2>&1") do
    allow_any_instance_of(SharePicture).to receive(:jpeg).and_call_original
    get plan_day_share_picture_path(1, 2, "day")
    expect(response.media_type).to eq("image/jpeg")
    expect(response.body.byteslice(0, 2).bytes).to eq([ 0xFF, 0xD8 ])
  end
end
