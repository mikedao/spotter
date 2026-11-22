require "rails_helper"

RSpec.describe "Posting a training-plan day to CompetitiveShooter.org" do
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

  it "opens the composer when the day is ticked done, and posts nothing by itself" do
    expect(CompetitiveShooter).not_to receive(:new)
    patch plan_workout_path(1, 2), params: { done: "1", note: "Felt steady" }
    expect(response).to redirect_to(plan_day_share_path(1, 2))
    expect(flash[:notice]).to include("Here's the post")
    follow_redirect!
    body = CGI.unescapeHTML(response.body)
    expect(body).to include("Post the day to CompetitiveShooter.org", "Training plan, week 1 day 2: Hold and trigger (Pardini)",
                            "✓ Hold drills: 10 of 10 holds of 8 s", "Felt steady", "Show my note on it", "Plan progress")
    expect(user.shared_posts).to be_empty
  end

  it "offers the day, the plan's progress and the sessions' pictures, the default ones ticked" do
    get plan_day_share_path(1, 2)
    page = Nokogiri::HTML(response.body)
    expect(page.css("[data-kind]").map { it["data-kind"] }).to eq(%w[ day progress ])
    expect(page.css("input[name='pictures[]'][checked]").map { it["value"] }).to eq(%w[ day ])
    expect(page.css("input[name='topics[]'][checked]").map { it["value"] }).to eq(%w[ international-issf-pistol bullseye-precision-pistol ])
  end

  it "posts the pictures, caption, topics and look picked in the composer" do
    expect(client).to receive(:post!).once do |body:, topics:, images:|
      expect(body).to eq("My own words")
      expect(topics).to eq(%w[ bullseye-precision-pistol ])
      expect(images.map(&:first)).to eq(%w[ spotter-plan-day.jpg spotter-plan-progress.jpg ])
      posted
    end
    expect(PlanDayPicture).to receive(:new).and_wrap_original do |original, share, look:|
      expect(look).to have_attributes(colors: "forest", identity: false, headline: "A good day", note: false, progress: true)
      original.call(share, look:)
    end

    post plan_day_share_path(1, 2), params: { pictures: %w[ progress day made-up ], body: "My own words", topics: %w[ bullseye-precision-pistol ],
                                              colors: "forest", identity: %w[ 0 ], headline: "A good day", show_note: %w[ 0 ], show_progress: %w[ 0 1 ] }
    expect(response).to redirect_to(plan_workout_path(1, 2))
    expect(user.shared_posts.sole).to have_attributes(post_id: "p9", plan_week: 1, plan_day: 2, pictures: %w[ day progress ])
    expect(user.reload.share_colors).to eq("forest")

    patch plan_workout_path(1, 2), params: { done: "1", note: "Edited" }
    expect(response).to redirect_to(plan_workout_path(1, 2))   # posted already: no composer again
    follow_redirect!
    expect(response.body).to include("Posted to CompetitiveShooter.org", posted["url"])
  end

  it "keeps everything picked when the post fails, and says why" do
    allow(client).to receive(:post!).and_raise(CompetitiveShooter::Error, "That's CompetitiveShooter.org's limit of 10 posts an hour.")
    post plan_day_share_path(1, 2), params: { pictures: %w[ progress ], body: "Kept", colors: "crimson", headline: "Kept too" }
    expect(response).to redirect_to(plan_day_share_path(1, 2, pictures: %w[ progress ], body: "Kept", topics: [],
                                                        colors: "crimson", identity: 1, headline: "Kept too", show_note: 1, show_progress: 1))
    follow_redirect!
    body = CGI.unescapeHTML(response.body)
    expect(body).to include("limit of 10 posts", "Kept", 'value="Kept too"')
    expect(user.shared_posts).to be_empty
  end

  it "refuses a post with no picture" do
    post plan_day_share_path(1, 2), params: { body: "x" }
    expect(flash[:alert]).to eq("Pick at least one picture to post.")
  end

  it "draws the day's card as picked: a headline of your own, no note, no progress, no name" do
    user.plan_enrollment.workouts.create!(week: 1, day: 2, completed_at: Time.current, note: "Steady today")
    share = PlanDayShare.new(user, 1, 2)
    plain = Nokogiri::XML(share.picture("day").svg).text
    expect(plain).to include("Hold and trigger (Pardini)", "10/10", "25/25", "4/4", "96% first time", "Steady today", "days done", "Logged with Spotter")

    look = PlanDayShare::Look.from({ headline: "Trigger day", show_note: "0", show_progress: "0", identity: "0" }, user)
    custom = Nokogiri::XML(share.picture("day", look:).svg).text
    expect(custom).to include("Trigger day", "Hold and trigger (Pardini)")
    expect(custom).not_to include("Steady today", "days done", user.display_name)
  end

  it "draws the plan's progress: every week, this day ringed, the run of days done" do
    enrollment = user.plan_enrollment
    enrollment.workouts.create!(week: 1, day: 1, completed_at: Time.current)
    enrollment.workouts.create!(week: 1, day: 2, completed_at: Time.current)
    enrollment.make_match!("2-7")
    text = Nokogiri::XML(PlanDayShare.new(user, 1, 2).picture("progress").svg).text
    expect(text).to include("W1", "W12", "2in a row".sub("in", " in"), "M match")
    expect(text).to include("2/84").or include("2/#{enrollment.workout_count}")
  end

  it "adds the sessions' target and numbers when air pistol was shot for the day" do
    session = create(:practice_session, user:, status: "ended", ended_at: Time.current, plan_week: 1, plan_day: 1, plan_block: 3)   # Steady-pace series
    card = create(:card, practice_session: session, number: 1)
    5.times { |i| create(:shot, card:, number: i + 1, ring: 9, decimal_score: 9.3, x_mm: i * 2.0, y_mm: 1.0) }
    share = PlanDayShare.new(user, 1, 1)
    expect(share.picture_kinds).to eq(%w[ day hero stats ])
    expect(share.topics).to eq([ "international-issf-pistol" ])
  end

  it "posts the groups, not a score, for a day shot in 5-shot groups" do
    session = create(:practice_session, user:, status: "ended", ended_at: Time.current, plan_week: 1, plan_day: 1, plan_block: 2)   # Slow groups
    card = create(:card, practice_session: session, number: 1)
    10.times { |i| create(:shot, card:, number: i + 1, ring: 9, decimal_score: 9.3, x_mm: (i % 5) * (i < 5 ? 2.0 : 4.0), y_mm: 1.0, fired_at: Time.current + i * 30) }
    share = PlanDayShare.new(user, 1, 1)
    expect(share.picture_kinds).to eq(%w[ day groups ])
    item = share.items.find { it.name == "Slow groups" }
    expect(item.value).to eq("8.0 mm")
    expect(item.line).to eq("2 groups of 5, best 8.0 mm, avg 12.0 mm")
    expect(share.body).to include("Slow groups: 2 groups of 5, best 8.0 mm")
  end

  it "serves the day's picture as a JPEG", if: system("which rsvg-convert > /dev/null 2>&1") do
    allow_any_instance_of(SharePicture).to receive(:jpeg).and_call_original
    get plan_day_share_picture_path(1, 2, "day")
    expect(response.media_type).to eq("image/jpeg")
    expect(response.body.byteslice(0, 2).bytes).to eq([ 0xFF, 0xD8 ])
  end
end
