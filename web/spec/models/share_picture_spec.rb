require "rails_helper"

RSpec.describe SharePicture do
  let(:user) { create(:user, name: "Ada Shooter") }
  let(:session) do
    s = create(:practice_session, user:, status: "ended", ended_at: Time.current)
    3.times do |n|
      card = create(:card, practice_session: s, number: n + 1)
      10.times { |i| create(:shot, card:, number: i + 1, ring: 10 - (i % 4), decimal_score: 10.2 - (i % 4), x_mm: (i - 5) * 3.0, y_mm: (n - 1) * 4.0) }
    end
    s
  end
  let(:set) { ShareSet.find(user, [ session.id ]) }

  SharePicture::KINDS.each_key do |kind|
    it "draws #{kind} as well-formed SVG with the total on it" do
      svg = SharePicture.build(kind, set, colors: "midnight").svg
      doc = Nokogiri::XML(svg) { it.strict }
      expect(doc.root.name).to eq("svg")
      expect(doc.text).to include(set.total_text)
    end
  end

  it "puts the name on only when asked" do
    expect(SharePicture.build("hero", set).svg).to include("Ada Shooter")
    expect(SharePicture.build("hero", set, identity: false).svg).not_to include("Ada Shooter")
  end

  it "escapes what the shooter typed" do
    user.update!(name: "<b>&")
    expect(SharePicture.build("scorecard", set).svg).to include("&lt;b&gt;&amp;")
  end

  it "falls back to the default colorway for an unknown one" do
    expect(SharePicture.build("stats", set, colors: "nope").theme).to eq(ShareColorway.find("midnight"))
  end

  describe "group training" do
    # Two cards of 10 shot as 5-shot groups: four groups, the second the tightest.
    before do
      session.update!(group_of: 5)
      session.cards.where(number: 3).destroy_all
      session.cards.each do |card|
        card.shots.each_with_index { |shot, i| shot.update!(x_mm: (i % 5) * (i < 5 ? 3.0 : 1.0), y_mm: card.number * 2.0) }
      end
    end

    let(:set) { ShareSet.find(user, [ session.id ]) }

    it "offers the groups instead of the score pictures" do
      expect(set).to be_grouped
      expect(SharePicture.kinds_for(set).keys).to eq(%w[ groups cards stats ])
      expect(SharePicture.kinds_for(ShareSet.find(user, [ create_ungrouped.id ])).keys).to eq(SharePicture::KINDS.keys)
    end

    it "draws each group with its size, the best marked, and no score" do
      expect(set.groups.map(&:size_mm)).to eq([ 12.0, 4.0, 12.0, 4.0 ])
      svg = SharePicture.build("groups", set).svg
      doc = Nokogiri::XML(svg) { it.strict }
      expect(doc.text).to include("GROUPS OF 5", "G2 · best", "4.0 mm", "avg 8.0 mm", "12.0 mm")
      expect(doc.text).not_to include(set.total_text)
    end
  end

  def create_ungrouped
    s = create(:practice_session, user:, status: "ended", ended_at: Time.current)
    card = create(:card, practice_session: s)
    10.times { |i| create(:shot, card:, number: i + 1, x_mm: i * 1.0) }
    s
  end

  it "turns into a JPEG", if: system("which rsvg-convert > /dev/null 2>&1") do
    jpeg = SharePicture.build("hero", set, colors: "paper").jpeg
    expect(jpeg.byteslice(0, 2).bytes).to eq([ 0xFF, 0xD8 ])
    expect(Vips::Image.new_from_buffer(jpeg, "").width).to eq(SharePicture::W)
  end
end
