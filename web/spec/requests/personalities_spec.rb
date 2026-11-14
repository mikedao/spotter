require "rails_helper"

RSpec.describe "Announcer personalities" do
  let(:user) { create(:user, voice: "bm_george") }

  before do
    sign_in(user)
    allow(Personality).to receive(:ensure!)
    allow(Personality).to receive(:health).and_return({ "ready" => true, "prepared" => 120, "of" => 2654 })
  end

  it "shows a Personalities section above the voices, None chosen by default" do
    allow(Personality).to receive(:trained?).and_return(true)
    get settings_path
    body = response.body
    expect(body.index("Personalities")).to be < body.index("Heart")
    expect(body).to include("Katey", "Nicole's voice", "Getting ready: 120 of 2,654")
    none = body[/<input[^>]*id="personality_"[^>]*>/]
    expect(none).to include('value=""', "checked")
  end

  it "chooses one and starts it; the voice picker keeps the user's own voice" do
    allow(Personality).to receive(:trained?).and_return(true)
    patch personality_path, params: { personality: "katey" }
    expect(user.reload.personality).to eq "katey"
    expect(Personality).to have_received(:ensure!).with("katey")
    follow_redirect!
    expect(response.body).to include("Your announcer is now Katey", "Katey speaks in Nicole's voice")
    expect(response.body).to match(/value="bm_george"[^>]*checked|checked[^>]*value="bm_george"/)
  end

  it "goes back to none, and refuses one that doesn't exist" do
    user.update!(personality: "katey")
    patch personality_path, params: { personality: "" }
    expect(user.reload.personality).to be_nil
    patch personality_path, params: { personality: "nobody" }
    expect(user.reload.personality).to be_nil
    follow_redirect!
    expect(response.body).to include("isn&#39;t one of the personalities")
  end

  it "says when its model isn't trained on this computer" do
    allow(Personality).to receive(:trained?).and_return(false)
    get settings_path
    expect(response.body).to include("Not set up on this computer")
  end
end
