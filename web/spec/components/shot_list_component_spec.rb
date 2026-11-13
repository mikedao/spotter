require "rails_helper"
require "view_component/test_helpers"

# Each scored shot says how the engine came to score it: heard (a sound), seen
# (the camera check, no sound before it), or seen/heard (a sound whose picture
# came too early, then the camera check found it - the Pi stream's lag).
RSpec.describe ShotListComponent, type: :component do
  include ViewComponent::TestHelpers

  let(:card) { create(:card) }

  it "says heard, seen or seen/heard for each shot" do
    heard = create(:shot, card:, trigger: "sound")
    seen = create(:shot, card:, trigger: "camera")
    both = create(:shot, card:, trigger: "sound_camera")
    render_inline(described_class.new(shots: [ heard, seen, both ]))
    expect(page.text.squish).to match(%r{seen/heard.*seen.*heard})   # newest first
    expect([ heard, seen, both ].map(&:found_by)).to eq %w[ heard seen seen/heard ]
  end

  it "accepts the engine's sound_camera trigger and calls the final check's find seen" do
    expect(build(:shot, card:, trigger: "sound_camera")).to be_valid
    expect(build(:shot, card:, trigger: "final_check").found_by).to eq "seen"
  end
end
