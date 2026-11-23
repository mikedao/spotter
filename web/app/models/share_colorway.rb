# The colorways of the pictures Spotter posts to CompetitiveShooter.org, copied from
# fl-shooters (app/models/share_colorway.rb) so a post from Spotter looks like one
# shared on the site. Keep the two in step. Spotter's own differences: "midnight"
# (Spotter's first default, kept so a saved choice still works) is the default here,
# and the overlay JSON (fl-shooters' canvas band) is left out - Spotter's previews are
# drawn on the server.
class ShareColorway
  # What a colorway sets; every colour on the poster comes from one of these (trophies keep their metals).
  # `accent` fills shapes that carry `on_accent` text and the band's bar; `highlight` is the accent
  # drawn straight on the background (headings, bars, dots), the same colour unless the accent is
  # too dark to read there, as Site blue's brand blue is on its navy.
  Theme = Data.define(:label, :bg1, :bg2, :glow, :ring, :ring_op, :accent, :highlight, :on_accent, :text, :muted, :sub,
                      :row, :row_op, :edge, :edge_op, :disc, :disc_text, :star, :medals, :bold) do
    # `bold: true` puts a theme in the pickers' Bold row (saturated colour, dark or light); the rest are
    # sorted by their background.
    def initialize(bold: false, **) = super

    # A light theme: dark text reads better than white on its background.
    def light? = ShareColorway.contrast(bg1, "#000000") > ShareColorway.contrast(bg1, "#ffffff")
  end

  # Medal colours, each set checked against its themes' backgrounds by the spec: bright metals on dark
  # themes, deep ones on light themes (where a bright gold vanished on the cream), a rose-gold bronze
  # on saturated white-text themes (plain bronze is as bright as a red or orange), and near-black
  # metals on the bright dark-text bold themes.
  DARK_MEDALS = { 1 => "#f5c542", 2 => "#cbd5e1", 3 => "#d08a4e" }.freeze
  LIGHT_MEDALS = { 1 => "#8a6200", 2 => "#5b6673", 3 => "#8f4e22" }.freeze
  BOLD_MEDALS = DARK_MEDALS.merge(3 => "#f7c39a").freeze
  DEEP_MEDALS = { 1 => "#4f3700", 2 => "#2f353c", 3 => "#542508" }.freeze

  # In picker order: Dark, Light, Bold (`rows`).
  THEMES = {
    # Dark
    "classic" => Theme.new(label: "Site blue", bg1: "#14305a", bg2: "#15202b", glow: "#3d5a80", ring: "#ffffff", ring_op: 0.08, accent: "#3d5a80", highlight: "#8fb3e0", on_accent: "#ffffff",
                           text: "#ffffff", muted: "#94a3b8", sub: "#cbd5e1", row: "#ffffff", row_op: 0.06, edge: "#ffffff", edge_op: 0.12, disc: "#334155", disc_text: "#e2e8f0",
                           star: "#a9c6ea", medals: DARK_MEDALS),
    "midnight" => Theme.new(label: "Midnight", bg1: "#14305a", bg2: "#070f1f", glow: "#f59e0b", ring: "#ffffff", ring_op: 0.08, accent: "#f59e0b", highlight: "#f59e0b", on_accent: "#0b1220",
                            text: "#ffffff", muted: "#94a3b8", sub: "#cbd5e1", row: "#ffffff", row_op: 0.06, edge: "#ffffff", edge_op: 0.12, disc: "#334155", disc_text: "#e2e8f0",
                            star: "#fbbf24", medals: DARK_MEDALS),
    "gunmetal" => Theme.new(label: "Gunmetal", bg1: "#30343c", bg2: "#0b0c0f", glow: "#f97316", ring: "#ffffff", ring_op: 0.06, accent: "#f97316", highlight: "#f97316", on_accent: "#160a02",
                            text: "#f5f5f4", muted: "#a1a1aa", sub: "#d4d4d8", row: "#ffffff", row_op: 0.06, edge: "#ffffff", edge_op: 0.12, disc: "#3f444d", disc_text: "#e4e4e7",
                            star: "#fb923c", medals: { 1 => "#f5c542", 2 => "#d4d4d8", 3 => "#d08a4e" }),
    "forest" => Theme.new(label: "Range green", bg1: "#24472f", bg2: "#08170d", glow: "#d4a537", ring: "#ffffff", ring_op: 0.07, accent: "#d4a537", highlight: "#d4a537", on_accent: "#10200f",
                          text: "#f4f7f1", muted: "#9bb5a2", sub: "#c8d9cc", row: "#ffffff", row_op: 0.07, edge: "#ffffff", edge_op: 0.13, disc: "#2f5a3d", disc_text: "#dcebe0",
                          star: "#e6c45c", medals: { 1 => "#f0c53f", 2 => "#cfd8d2", 3 => "#cf8d52" }),
    "crimson" => Theme.new(label: "Crimson", bg1: "#611524", bg2: "#17040a", glow: "#ef4444", ring: "#ffffff", ring_op: 0.07, accent: "#fbbf24", highlight: "#fbbf24", on_accent: "#2a0a0f",
                           text: "#fff7f7", muted: "#d6a3ab", sub: "#efc9cf", row: "#ffffff", row_op: 0.07, edge: "#ffffff", edge_op: 0.14, disc: "#7a2535", disc_text: "#fde4e7",
                           star: "#fcd34d", medals: { 1 => "#fbc531", 2 => "#e5e7eb", 3 => "#d98e55" }),
    "coyote" => Theme.new(label: "Coyote", bg1: "#4d3c29", bg2: "#1a130b", glow: "#c8a26b", ring: "#ffffff", ring_op: 0.07, accent: "#c8a26b", highlight: "#c8a26b", on_accent: "#1a130b",
                          text: "#f7f1e6", muted: "#b3a48c", sub: "#dccfb8", row: "#ffffff", row_op: 0.06, edge: "#ffffff", edge_op: 0.12, disc: "#5c4a35", disc_text: "#f1e6d2",
                          star: "#e0c28f", medals: DARK_MEDALS),
    "black" => Theme.new(label: "Match black", bg1: "#1f1f1f", bg2: "#000000", glow: "#d4af37", ring: "#ffffff", ring_op: 0.06, accent: "#d4af37", highlight: "#d4af37", on_accent: "#000000",
                         text: "#ffffff", muted: "#9ca3af", sub: "#d1d5db", row: "#ffffff", row_op: 0.05, edge: "#ffffff", edge_op: 0.1, disc: "#2e2e2e", disc_text: "#e5e5e5",
                         star: "#e8c766", medals: DARK_MEDALS),
    "cobalt" => Theme.new(label: "Cobalt", bg1: "#1d4ed8", bg2: "#0c1f6b", glow: "#60a5fa", ring: "#ffffff", ring_op: 0.1, accent: "#ffffff", highlight: "#ffffff", on_accent: "#1e3a8a",
                          text: "#ffffff", muted: "#bfdbfe", sub: "#dbeafe", row: "#ffffff", row_op: 0.08, edge: "#ffffff", edge_op: 0.16, disc: "#1e3a8a", disc_text: "#e0e7ff",
                          star: "#fde68a", medals: { 1 => "#f5c542", 2 => "#cbd5e1", 3 => "#f2a66a" }),
    "plum" => Theme.new(label: "Plum", bg1: "#4c1d5e", bg2: "#16051f", glow: "#f472b6", ring: "#ffffff", ring_op: 0.07, accent: "#f472b6", highlight: "#f472b6", on_accent: "#2a0a2e",
                        text: "#fdf4ff", muted: "#c4a6cf", sub: "#e9d5f0", row: "#ffffff", row_op: 0.06, edge: "#ffffff", edge_op: 0.12, disc: "#5e2a72", disc_text: "#f5e8fa",
                        star: "#f9a8d4", medals: DARK_MEDALS),
    "patriot" => Theme.new(label: "Red, white & blue", bg1: "#1b2f5c", bg2: "#0a1430", glow: "#b22234", ring: "#ffffff", ring_op: 0.08, accent: "#b22234", highlight: "#ff6b6b", on_accent: "#ffffff",
                           text: "#ffffff", muted: "#a9b6cf", sub: "#d6deec", row: "#ffffff", row_op: 0.06, edge: "#ffffff", edge_op: 0.12, disc: "#2a4070", disc_text: "#e8edf6",
                           star: "#ff8a8a", medals: DARK_MEDALS),
    "tritium" => Theme.new(label: "Tritium", bg1: "#0f2a1c", bg2: "#030a06", glow: "#39ff88", ring: "#ffffff", ring_op: 0.07, accent: "#39ff88", highlight: "#39ff88", on_accent: "#03140a",
                           text: "#effff5", muted: "#8fb59e", sub: "#cfe8d8", row: "#ffffff", row_op: 0.06, edge: "#ffffff", edge_op: 0.12, disc: "#1d3d2b", disc_text: "#d9f5e4",
                           star: "#7dffb0", medals: DARK_MEDALS),
    "lagoon" => Theme.new(label: "Lagoon", bg1: "#0f4c5c", bg2: "#04191f", glow: "#ff7f66", ring: "#ffffff", ring_op: 0.07, accent: "#ff7f66", highlight: "#ff7f66", on_accent: "#2a0d07",
                          text: "#f0fbfc", muted: "#94bcc4", sub: "#cfe7eb", row: "#ffffff", row_op: 0.06, edge: "#ffffff", edge_op: 0.12, disc: "#1b5f70", disc_text: "#e0f3f6",
                          star: "#ffb3a3", medals: DARK_MEDALS),
    "olive" => Theme.new(label: "Olive drab", bg1: "#4b5320", bg2: "#1a1d0a", glow: "#e8dcb0", ring: "#ffffff", ring_op: 0.07, accent: "#e8dcb0", highlight: "#e8dcb0", on_accent: "#1a1d0a",
                         text: "#f7f6ec", muted: "#b8b78f", sub: "#dedcc0", row: "#ffffff", row_op: 0.06, edge: "#ffffff", edge_op: 0.12, disc: "#5d6630", disc_text: "#f0efdc",
                         star: "#efe6c0", medals: { 1 => "#f5c542", 2 => "#cbd5e1", 3 => "#e3a06a" }),
    # Light
    "paper" => Theme.new(label: "Paper target", bg1: "#f4ecd6", bg2: "#e0d1ab", glow: "#b45309", ring: "#6b5a3a", ring_op: 0.16, accent: "#9a3412", highlight: "#9a3412", on_accent: "#fff7e6",
                         text: "#1c1917", muted: "#6b5a3a", sub: "#44392a", row: "#ffffff", row_op: 0.55, edge: "#6b5a3a", edge_op: 0.3, disc: "#6b5a3a", disc_text: "#f6edd5",
                         star: "#b45309", medals: LIGHT_MEDALS),
    "daylight" => Theme.new(label: "Daylight", bg1: "#ffffff", bg2: "#e3e9f1", glow: "#8fb3e0", ring: "#1e3a5f", ring_op: 0.12, accent: "#3d5a80", highlight: "#3d5a80", on_accent: "#ffffff",
                            text: "#0f172a", muted: "#5a6879", sub: "#334155", row: "#ffffff", row_op: 0.6, edge: "#1e3a5f", edge_op: 0.2, disc: "#3d5a80", disc_text: "#ffffff",
                            star: "#2f4a6e", medals: LIGHT_MEDALS),
    "sky" => Theme.new(label: "Sky", bg1: "#e3f0fd", bg2: "#b7d4f2", glow: "#ffffff", ring: "#0b2545", ring_op: 0.12, accent: "#0b2545", highlight: "#0b2545", on_accent: "#ffffff",
                       text: "#0b1a30", muted: "#3b5470", sub: "#1f3a5a", row: "#ffffff", row_op: 0.6, edge: "#0b2545", edge_op: 0.2, disc: "#1d4e89", disc_text: "#ffffff",
                       star: "#1d4e89", medals: LIGHT_MEDALS),
    "steel" => Theme.new(label: "Steel", bg1: "#f3f4f6", bg2: "#cdd3da", glow: "#ef4444", ring: "#1f2937", ring_op: 0.12, accent: "#b91c1c", highlight: "#b91c1c", on_accent: "#ffffff",
                         text: "#111827", muted: "#4b5563", sub: "#1f2937", row: "#ffffff", row_op: 0.6, edge: "#1f2937", edge_op: 0.2, disc: "#374151", disc_text: "#f9fafb",
                         star: "#b91c1c", medals: LIGHT_MEDALS),
    "sand" => Theme.new(label: "Sand", bg1: "#f0e8d5", bg2: "#d8c9a6", glow: "#6b7f3a", ring: "#3d3a22", ring_op: 0.14, accent: "#4b5d23", highlight: "#4b5d23", on_accent: "#ffffff",
                        text: "#1f1d14", muted: "#5a533d", sub: "#3a3626", row: "#ffffff", row_op: 0.5, edge: "#3d3a22", edge_op: 0.25, disc: "#4b5d23", disc_text: "#f4f0e0",
                        star: "#4b5d23", medals: LIGHT_MEDALS),
    "mint" => Theme.new(label: "Mint", bg1: "#eefaf2", bg2: "#c6ead3", glow: "#2f855a", ring: "#14532d", ring_op: 0.12, accent: "#166534", highlight: "#166534", on_accent: "#ffffff",
                        text: "#0c1f14", muted: "#3f5f4b", sub: "#1f3a2a", row: "#ffffff", row_op: 0.6, edge: "#14532d", edge_op: 0.2, disc: "#166534", disc_text: "#ffffff",
                        star: "#166534", medals: LIGHT_MEDALS),
    "rose" => Theme.new(label: "Rose", bg1: "#fdf0f2", bg2: "#f3cdd5", glow: "#e11d48", ring: "#4c0519", ring_op: 0.12, accent: "#9f1239", highlight: "#9f1239", on_accent: "#ffffff",
                        text: "#2a0a12", muted: "#6e3a47", sub: "#4a1d28", row: "#ffffff", row_op: 0.6, edge: "#4c0519", edge_op: 0.2, disc: "#9f1239", disc_text: "#ffffff",
                        star: "#9f1239", medals: LIGHT_MEDALS),
    "lavender" => Theme.new(label: "Lavender", bg1: "#f5f0ff", bg2: "#d9cdf5", glow: "#7c3aed", ring: "#2e1065", ring_op: 0.12, accent: "#5b21b6", highlight: "#5b21b6", on_accent: "#ffffff",
                            text: "#1a0b38", muted: "#55487a", sub: "#33275a", row: "#ffffff", row_op: 0.6, edge: "#2e1065", edge_op: 0.2, disc: "#5b21b6", disc_text: "#ffffff",
                            star: "#5b21b6", medals: LIGHT_MEDALS),
    "hivis" => Theme.new(label: "Hi-vis", bg1: "#fff27a", bg2: "#f5d90a", glow: "#ffffff", ring: "#1a1a00", ring_op: 0.12, accent: "#111111", highlight: "#111111", on_accent: "#fff27a",
                         text: "#111111", muted: "#4a4300", sub: "#2b2700", row: "#ffffff", row_op: 0.45, edge: "#111111", edge_op: 0.2, disc: "#111111", disc_text: "#fff27a",
                         star: "#111111", medals: LIGHT_MEDALS),
    # Bold
    "fire" => Theme.new(label: "Fire red", bg1: "#c81e1e", bg2: "#6e0b0b", glow: "#fde047", ring: "#ffffff", ring_op: 0.12, accent: "#fde047", highlight: "#fde047", on_accent: "#3a0505",
                        text: "#ffffff", muted: "#fecaca", sub: "#fee2e2", row: "#ffffff", row_op: 0.1, edge: "#ffffff", edge_op: 0.2, disc: "#8f1414", disc_text: "#fff1f1",
                        star: "#fde047", medals: BOLD_MEDALS, bold: true),
    "electric" => Theme.new(label: "Electric purple", bg1: "#6d28d9", bg2: "#2e1065", glow: "#facc15", ring: "#ffffff", ring_op: 0.12, accent: "#facc15", highlight: "#facc15", on_accent: "#2e1065",
                            text: "#ffffff", muted: "#ddd6fe", sub: "#ede9fe", row: "#ffffff", row_op: 0.1, edge: "#ffffff", edge_op: 0.2, disc: "#4c1d95", disc_text: "#f5f3ff",
                            star: "#fde047", medals: BOLD_MEDALS, bold: true),
    "hotpink" => Theme.new(label: "Hot pink", bg1: "#c2185b", bg2: "#5c0630", glow: "#ffe066", ring: "#ffffff", ring_op: 0.12, accent: "#ffffff", highlight: "#ffffff", on_accent: "#9d174d",
                           text: "#ffffff", muted: "#fbcfe8", sub: "#fce7f3", row: "#ffffff", row_op: 0.1, edge: "#ffffff", edge_op: 0.2, disc: "#8a1145", disc_text: "#fff0f6",
                           star: "#ffe066", medals: BOLD_MEDALS, bold: true),
    "sunset" => Theme.new(label: "Sunset", bg1: "#c2410c", bg2: "#701a50", glow: "#fbbf24", ring: "#ffffff", ring_op: 0.12, accent: "#fbbf24", highlight: "#fde68a", on_accent: "#3b0a1f",
                          text: "#ffffff", muted: "#fed7aa", sub: "#ffedd5", row: "#ffffff", row_op: 0.1, edge: "#ffffff", edge_op: 0.2, disc: "#8a2a3a", disc_text: "#fff1e6",
                          star: "#fde68a", medals: BOLD_MEDALS, bold: true),
    "synthwave" => Theme.new(label: "Synthwave", bg1: "#3b0f7a", bg2: "#12032b", glow: "#ff2bd6", ring: "#ffffff", ring_op: 0.12, accent: "#ff2bd6", highlight: "#ff5ce1", on_accent: "#1a0033",
                             text: "#ffffff", muted: "#c4b5fd", sub: "#e9d5ff", row: "#ffffff", row_op: 0.1, edge: "#ffffff", edge_op: 0.2, disc: "#4c1d95", disc_text: "#f5f3ff",
                             star: "#22e5ff", medals: BOLD_MEDALS, bold: true),
    "tropical" => Theme.new(label: "Tropical", bg1: "#0f766e", bg2: "#14532d", glow: "#fde047", ring: "#ffffff", ring_op: 0.12, accent: "#fde047", highlight: "#fde047", on_accent: "#052e1a",
                            text: "#ffffff", muted: "#a7f3d0", sub: "#d1fae5", row: "#ffffff", row_op: 0.1, edge: "#ffffff", edge_op: 0.2, disc: "#115e59", disc_text: "#ecfdf5",
                            star: "#fde047", medals: BOLD_MEDALS, bold: true),
    "blaze" => Theme.new(label: "Blaze orange", bg1: "#ff8a1f", bg2: "#f26a0a", glow: "#ffe08a", ring: "#2a1000", ring_op: 0.14, accent: "#1a0a00", highlight: "#1a0a00", on_accent: "#ff9a3c",
                         text: "#1a0a00", muted: "#4a1f00", sub: "#2e1300", row: "#ffffff", row_op: 0.3, edge: "#1a0a00", edge_op: 0.25, disc: "#1a0a00", disc_text: "#ffb066",
                         star: "#1a0a00", medals: DEEP_MEDALS, bold: true),
    "lime" => Theme.new(label: "Lime", bg1: "#c4f25a", bg2: "#8ccf17", glow: "#ffffff", ring: "#1a2e05", ring_op: 0.14, accent: "#1a2e05", highlight: "#1a2e05", on_accent: "#c4f25a",
                        text: "#0f1a03", muted: "#2f4a0c", sub: "#1f3308", row: "#ffffff", row_op: 0.3, edge: "#1a2e05", edge_op: 0.25, disc: "#1a2e05", disc_text: "#d9f99d",
                        star: "#1a2e05", medals: DEEP_MEDALS, bold: true),
    "aqua" => Theme.new(label: "Aqua", bg1: "#5ee3f5", bg2: "#14bcd6", glow: "#ffffff", ring: "#083344", ring_op: 0.14, accent: "#083344", highlight: "#083344", on_accent: "#a5f3fc",
                        text: "#04212b", muted: "#0b4a5c", sub: "#073847", row: "#ffffff", row_op: 0.3, edge: "#083344", edge_op: 0.25, disc: "#083344", disc_text: "#cffafe",
                        star: "#083344", medals: DEEP_MEDALS, bold: true),
    "bubblegum" => Theme.new(label: "Bubblegum", bg1: "#ffc2e2", bg2: "#ff8cc6", glow: "#ffffff", ring: "#5c0632", ring_op: 0.14, accent: "#831843", highlight: "#831843", on_accent: "#ffffff",
                             text: "#2a0516", muted: "#6b1d43", sub: "#4a0d2c", row: "#ffffff", row_op: 0.3, edge: "#5c0632", edge_op: 0.25, disc: "#831843", disc_text: "#ffffff",
                             star: "#831843", medals: DEEP_MEDALS, bold: true)
  }.freeze

  # WCAG contrast ratio between two "#rrggbb" colours (1 to 21); the spec holds every theme to floors.
  def self.contrast(a, b)
    hi, lo = [ luminance(a), luminance(b) ].sort.reverse
    (hi + 0.05) / (lo + 0.05)
  end

  # The numeral colour for a disc filled with `color` (a medal): dark slate, unless white reads better,
  # as it does on a light theme's deep metals.
  def self.ink_on(color) = contrast(color, INK_DARK) >= contrast(color, "#ffffff") ? INK_DARK : "#ffffff"

  INK_DARK = "#1e293b"

  def self.luminance(hex)
    r, g, b = hex.delete("#").scan(/../).map do |pair|
      c = pair.to_i(16) / 255.0
      c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4
    end
    0.2126 * r + 0.7152 * g + 0.0722 * b
  end
  private_class_method :luminance

  # The themes as the pickers show them: the dark ones, the light ones, then the bold ones.
  def self.rows
    bold, plain = THEMES.partition { |_key, theme| theme.bold }.map(&:to_h)
    dark, light = plain.partition { |_key, theme| !theme.light? }.map(&:to_h)
    { "Dark" => dark, "Light" => light, "Bold" => bold }.reject { |_label, themes| themes.empty? }
  end

  DEFAULT = "midnight"

  def self.keys = THEMES.keys
  def self.find(key) = THEMES.fetch(key.to_s) { THEMES.fetch(DEFAULT) }
  def self.key_for(key) = THEMES.key?(key.to_s) ? key.to_s : DEFAULT
end
