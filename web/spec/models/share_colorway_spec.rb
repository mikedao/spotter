require "rails_helper"

# Copied from fl-shooters (spec/models/share_colorway_spec.rb). Every share picture is drawn from these colours, on a dark or a light background, so a theme that
# reads badly is caught here rather than on a member's poster. Floors are WCAG contrast ratios,
# checked against both ends of the background gradient: 4.5 for ordinary text, 3 for what is drawn
# large or bold (headings, rank numerals, trophy lines, the footer). Site blue's brand blue as a
# heading measured 1.9 before it got its own `highlight`.
RSpec.describe ShareColorway do
  text_floor = 4.5
  large_floor = 3.0

  def worst(theme, color) = [ described_class.contrast(color, theme.bg1), described_class.contrast(color, theme.bg2) ].min

  described_class::THEMES.each do |key, theme|
    describe "#{theme.label} (#{key})" do
      it "has readable text on its background" do
        expect(worst(theme, theme.text)).to be >= text_floor
        expect(worst(theme, theme.sub)).to be >= text_floor
      end

      it "has readable muted text, headings and trophy lines" do
        { muted: theme.muted, highlight: theme.highlight, star: theme.star }.each do |field, color|
          expect(worst(theme, color)).to be >= large_floor, "#{field} #{color}: #{worst(theme, color).round(2)}"
        end
      end

      it "has medals that read on the background, and numerals that read on the medals" do
        theme.medals.each do |place, color|
          expect(worst(theme, color)).to be >= large_floor, "medal #{place} #{color}: #{worst(theme, color).round(2)}"
          expect(described_class.contrast(described_class.ink_on(color), color)).to be >= text_floor, "numeral on medal #{place}"
        end
      end

      it "has readable text on its accent and on its rank discs" do
        expect(described_class.contrast(theme.on_accent, theme.accent)).to be >= text_floor
        expect(described_class.contrast(theme.disc_text, theme.disc)).to be >= text_floor
      end
    end
  end

  it "falls back to Midnight, Spotter's default, for an unknown key" do
    expect(described_class.find("nope")).to eq(described_class::THEMES.fetch("midnight"))
    expect(described_class.key_for("nope")).to eq("midnight")
    expect(described_class.key_for("synthwave")).to eq("synthwave")
  end

  it "has every one of fl-shooters' themes (kept in step), plus Midnight" do
    fl = Rails.root.join("../../fl-shooters/app/models/share_colorway.rb")
    skip "fl-shooters is not checked out beside spotter" unless fl.exist?
    theirs = fl.read.scan(/^    "(\w+)" => Theme\.new/).flatten
    expect(described_class::THEMES.keys - [ "midnight" ]).to eq(theirs)
  end

  it "sorts the themes into dark, light and bold rows" do
    rows = described_class.rows
    expect(rows.keys).to eq(%w[ Dark Light Bold ])
    expect(rows["Dark"].keys.first).to eq("classic")
    expect(rows["Light"]).to include("paper")
    expect(rows["Bold"]).to include("synthwave")
    expect(rows["Dark"].values).to all(satisfy { |t| !t.light? && !t.bold })
    expect(rows["Light"].values).to all(satisfy { |t| t.light? && !t.bold })
    expect(rows["Bold"].values).to all(satisfy(&:bold))
    expect(rows.values.flat_map(&:keys)).to match_array(described_class::THEMES.keys)
  end

  it "gives every theme its own name" do
    labels = described_class::THEMES.values.map(&:label)
    expect(labels).to eq(labels.uniq)
  end

  it "measures contrast the WCAG way" do
    expect(described_class.contrast("#000000", "#ffffff")).to be_within(0.01).of(21)
    expect(described_class.contrast("#3d5a80", "#14305a")).to be < 2
  end

  it "writes a dark numeral on a bright medal and a white one on a deep medal" do
    expect(described_class.ink_on("#f5c542")).to eq("#1e293b")
    expect(described_class.ink_on("#7a5600")).to eq("#ffffff")
  end
end
