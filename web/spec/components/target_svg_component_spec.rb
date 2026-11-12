require "rails_helper"
require "view_component/test_helpers"

# The range screen's zoom: framed on the black, out a whole ring at a time.
RSpec.describe TargetSvgComponent, type: :component do
  include ViewComponent::TestHelpers

  let(:pistol) { TargetSpec.fetch("pistol") }
  let(:rifle) { TargetSpec.fetch("rifle") }

  def shot(x, y) = build(:shot, x_mm: x, y_mm: y)

  def half_width(spec, shots, **)
    render_inline(described_class.new(spec:, shots:, **))
    rendered_content[/viewBox="([^"]+)"/, 1].split.last.to_f / 2
  end

  it "frames the black aiming mark before the first shot and while every shot is in it" do
    expect(half_width(pistol, [])).to eq(29.75 + 4)                     # ring 7 + half a ring
    expect(half_width(pistol, [ shot(0, 0), shot(-20, 15), shot(0, 30) ])).to eq(33.75)
    expect(half_width(rifle, [])).to eq(15.25 + 1.25)                   # rifle black = ring 4
  end

  it "steps out one whole ring, only as far as the widest shot needs" do
    expect(half_width(pistol, [ shot(0, 0), shot(34, 0) ])).to eq(37.75 + 4)    # ring 6
    expect(half_width(pistol, [ shot(0, 0), shot(-30, -30) ])).to eq(33.75)   # the square's corner holds it
    expect(half_width(pistol, [ shot(0, -60) ])).to eq(61.75 + 4)              # ring 3
  end

  it "never zooms out past the whole card, and :card always shows it" do
    expect(half_width(pistol, [ shot(0, 95) ])).to eq(77.75 + 4)
    expect(half_width(pistol, [ shot(0, 0) ], zoom: :card)).to eq(81.75)
  end
end
