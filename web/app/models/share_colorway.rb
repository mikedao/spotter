# The colorways of the pictures Spotter posts to CompetitiveShooter.org, copied from
# fl-shooters (app/models/share_colorway.rb) so a post from Spotter looks like one
# shared on the site: five themes, plus the site's own navy and blue as "classic".
# Keep the two in step.
class ShareColorway
  Theme = Data.define(:label, :bg1, :bg2, :glow, :ring, :ring_op, :accent, :on_accent, :text, :muted, :sub,
                      :row, :row_op, :edge, :edge_op, :disc, :disc_text, :star)

  THEMES = {
    "classic" => Theme.new(label: "Site blue", bg1: "#14305a", bg2: "#15202b", glow: "#3d5a80", ring: "#ffffff", ring_op: 0.08, accent: "#3d5a80", on_accent: "#ffffff",
                           text: "#ffffff", muted: "#94a3b8", sub: "#cbd5e1", row: "#ffffff", row_op: 0.06, edge: "#ffffff", edge_op: 0.12,
                           disc: "#334155", disc_text: "#e2e8f0", star: "#a9c6ea"),
    "midnight" => Theme.new(label: "Midnight", bg1: "#14305a", bg2: "#070f1f", glow: "#f59e0b", ring: "#ffffff", ring_op: 0.08, accent: "#f59e0b", on_accent: "#0b1220",
                            text: "#ffffff", muted: "#94a3b8", sub: "#cbd5e1", row: "#ffffff", row_op: 0.06, edge: "#ffffff", edge_op: 0.12,
                            disc: "#334155", disc_text: "#e2e8f0", star: "#fbbf24"),
    "gunmetal" => Theme.new(label: "Gunmetal", bg1: "#30343c", bg2: "#0b0c0f", glow: "#f97316", ring: "#ffffff", ring_op: 0.06, accent: "#f97316", on_accent: "#160a02",
                            text: "#f5f5f4", muted: "#a1a1aa", sub: "#d4d4d8", row: "#ffffff", row_op: 0.06, edge: "#ffffff", edge_op: 0.12,
                            disc: "#3f444d", disc_text: "#e4e4e7", star: "#fb923c"),
    "forest" => Theme.new(label: "Range green", bg1: "#24472f", bg2: "#08170d", glow: "#d4a537", ring: "#ffffff", ring_op: 0.07, accent: "#d4a537", on_accent: "#10200f",
                          text: "#f4f7f1", muted: "#9bb5a2", sub: "#c8d9cc", row: "#ffffff", row_op: 0.07, edge: "#ffffff", edge_op: 0.13,
                          disc: "#2f5a3d", disc_text: "#dcebe0", star: "#e6c45c"),
    "crimson" => Theme.new(label: "Crimson", bg1: "#611524", bg2: "#17040a", glow: "#ef4444", ring: "#ffffff", ring_op: 0.07, accent: "#fbbf24", on_accent: "#2a0a0f",
                           text: "#fff7f7", muted: "#d6a3ab", sub: "#efc9cf", row: "#ffffff", row_op: 0.07, edge: "#ffffff", edge_op: 0.14,
                           disc: "#7a2535", disc_text: "#fde4e7", star: "#fcd34d"),
    "paper" => Theme.new(label: "Paper target", bg1: "#f4ecd6", bg2: "#e0d1ab", glow: "#b45309", ring: "#6b5a3a", ring_op: 0.16, accent: "#9a3412", on_accent: "#fff7e6",
                         text: "#1c1917", muted: "#6b5a3a", sub: "#44392a", row: "#ffffff", row_op: 0.55, edge: "#6b5a3a", edge_op: 0.3,
                         disc: "#6b5a3a", disc_text: "#f6edd5", star: "#b45309")
  }.freeze

  DEFAULT = "midnight"

  def self.keys = THEMES.keys
  def self.find(key) = THEMES.fetch(key.to_s) { THEMES.fetch(DEFAULT) }
  def self.key_for(key) = THEMES.key?(key.to_s) ? key.to_s : DEFAULT
end
