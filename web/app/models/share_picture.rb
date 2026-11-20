# One picture of a post to CompetitiveShooter.org, drawn as SVG on the server in the
# look of fl-shooters' share pictures (its colorways, its score band) and turned
# into a JPEG by libvips. A post carries up to four (the site's limit):
#
#   hero       the whole set on one target, with fl-shooters' score band under it
#   scorecard  every series, shot by shot, with its total
#   stats      the numbers, where the shots went, and where the misses go
#   cards      each card's own target and score
#
#   SharePicture.build("hero", set, colors: "midnight", identity: true).jpeg
class SharePicture
  W = 1600
  MARGIN = 100
  MISS = "#b91c1c"   # a penalized shot, the scorecard's red (as fl-shooters' M chip)

  KINDS = {
    "hero" => "Target and score",
    "scorecard" => "Scorecard",
    "stats" => "The numbers",
    "cards" => "Every card"
  }.freeze

  def self.build(kind, set, colors: nil, identity: true)
    klass = { "hero" => Hero, "scorecard" => Scorecard, "stats" => Stats, "cards" => Cards }.fetch(kind.to_s)
    klass.new(set, colors:, identity:)
  end

  attr_reader :set, :theme

  def initialize(set, colors: nil, identity: true)
    @set = set
    @theme = ShareColorway.find(colors)
    @identity = identity
  end

  def identity? = @identity

  def svg
    body, height = draw
    ShareSvg.document(W, height, ShareSvg.backdrop(theme, W, height) + body)
  end

  def jpeg
    image = Vips::Image.pngload_buffer(png)
    image = image.flatten(background: hex_rgb(theme.bg2)) if image.has_alpha?
    image.jpegsave_buffer(Q: 90, strip: true)
  end

  class RenderError < StandardError; end

  # The SVG as a PNG, by librsvg's own command line. Not libvips' svgload: image_processing
  # blocks it as untrusted for the whole process (Vips.block_untrusted), and unblocking it
  # would let Active Storage read SVGs too.
  def png
    out, err, status = Open3.capture3("rsvg-convert", "--format=png", stdin_data: svg, binmode: true)
    raise RenderError, "rsvg-convert failed: #{err.strip}" unless status.success?

    out
  rescue Errno::ENOENT
    raise RenderError, "rsvg-convert is missing (brew install librsvg, or apt install librsvg2-bin)"
  end

  def filename = "spotter-#{self.class.name.demodulize.downcase}.jpg"

  private
    def t = theme
    def text(...) = ShareSvg.text(...)
    def eyebrow(...) = ShareSvg.eyebrow(...)
    def rect(...) = ShareSvg.rect(...)
    def tw(...) = ShareSvg.text_width(...)

    def hex_rgb(hex) = [ 1, 3, 5 ].map { hex[it, 2].to_i(16) }

    # The top of every picture but the hero: an eyebrow in the accent, the set's
    # title (shrinks, then wraps - never cut off), and who, when and how many.
    # Returns [ svg, y below it ].
    def header(label)
      parts = [ eyebrow(MARGIN, 170, label, 40, t.accent) ]
      lines, size = ShareSvg.lines_for(set.title, 92, W - 2 * MARGIN, 2, 56)
      y = 170 + 40 + size
      lines.each do |line|
        parts << text(MARGIN, y, line, size, t.text, weight: 800)
        y += (size * 1.12).round
      end
      sub = [ (set.session.user.display_name if identity?), set.date_text, set.meta ].compact.join("  ·  ")
      sub_lines, sub_size = ShareSvg.lines_for(sub, 42, W - 2 * MARGIN, 2, 30)
      y += 4
      sub_lines.each do |line|
        parts << text(MARGIN, y, line, sub_size, t.sub, weight: 500)
        y += (sub_size * 1.3).round
      end
      [ parts.join, y ]
    end

    # The bottom of every picture but the hero: the score on the left, Spotter's
    # mark on the right. `bottom` is the picture's height.
    def footer(bottom)
      main, rest = set.score_parts
      y = bottom - 90
      x = MARGIN
      parts = [ eyebrow(x, y - 92, set.whole_rings? ? "Total" : "Total (decimal)", 28, t.muted) ]
      parts << text(x, y, main, 96, t.text, weight: 800)
      x += tw(main, 96) + 10
      if set.out_of
        parts << text(x, y, "/#{set.out_of}", 52, t.text, weight: 700, opacity: 0.55)
        x += tw("/#{set.out_of}", 52) + 14
      end
      parts << text(x, y, rest, 52, t.star, weight: 700) if rest
      parts << ShareSvg.brand(W - MARGIN, y - 30, 64, t)
      parts.join
    end

    # --- the target -----------------------------------------------------------

    # The outermost ring in view, as the range screen frames it (TargetSvgComponent
    # zoom :fit): the black, then out a whole ring at a time only as far as the
    # farthest shot needs.
    def view_ring(shots)
      spec = set.spec
      margin = spec.step_mm / 2.0
      far = shots.map { [ it.final_x_mm.abs, it.final_y_mm.abs ].max }.max.to_f + TargetSpec::PELLET_MM / 2.0 + 0.5
      spec.black_ring.downto(1).find { far <= spec.ring_radius_mm(it) + margin } || 1
    end

    # The ISSF target in a `size` px square at x, y with `shots` on it at their final
    # positions, true pellet size: drawn in millimetres in a nested <svg> whose
    # viewBox frames out to `ring` (and clips anything past it).
    def target(x, y, size, shots, ring: view_ring(shots), numbers: true)
      spec = set.spec
      h = (spec.ring_radius_mm(ring) + spec.step_mm / 2.0).round(2)
      paper, line_paper, line_black = TargetSvgComponent::PAPER, TargetSvgComponent::LINE_ON_PAPER, TargetSvgComponent::LINE_ON_BLACK
      parts = [ %(<rect x="#{-h}" y="#{-h}" width="#{2 * h}" height="#{2 * h}" fill="#{paper}"/>),
                %(<circle r="#{spec.black_radius_mm}" fill="#111"/>) ]
      (1..10).each do |n|
        r = spec.ring_radius_mm(n)
        colour = r < spec.black_radius_mm - 0.01 ? line_black : line_paper
        parts << %(<circle r="#{r}" fill="none" stroke="#{colour}" stroke-width="0.25"/>)
      end
      parts << %(<circle r="#{spec.inner_ten_radius_mm}" fill="none" stroke="#{line_black}" stroke-width="0.2"/>)
      parts << ring_numbers(spec, ring, line_paper, line_black) if numbers
      r = TargetSpec::PELLET_MM / 2.0
      shots.each do |s|
        cx, cy = s.final_x_mm.round(2), -s.final_y_mm.round(2)
        parts << %(<circle cx="#{cx}" cy="#{cy}" r="#{r + 0.25}" fill="#000" fill-opacity="0.45"/>)
        parts << %(<circle cx="#{cx}" cy="#{cy}" r="#{r}" fill="#{shot_colour}" fill-opacity="0.92" stroke="#fff" stroke-width="0.32"/>)
      end
      %(<svg x="#{x.round(2)}" y="#{y.round(2)}" width="#{size.round(2)}" height="#{size.round(2)}" viewBox="#{-h} #{-h} #{2 * h} #{2 * h}">#{parts.join}</svg>)
    end

    # The shots in the colorway's accent - except where it would vanish on the black
    # (the site blue): there the range screen's own blue.
    def shot_colour = t == ShareColorway::THEMES["classic"] ? TargetSvgComponent::SHOT : t.accent

    # 1-8 in the middle of each band on the four axes, as printed (TargetSvgComponent).
    def ring_numbers(spec, ring, line_paper, line_black)
      size = (spec.step_mm * 0.45).round(2)
      (ring..8).flat_map do |n|
        mid = ((spec.ring_radius_mm(n) + spec.ring_radius_mm(n + 1)) / 2.0).round(2)
        colour = spec.ring_radius_mm(n) <= spec.black_radius_mm + 0.01 ? line_black : line_paper
        [ [ -mid, 0 ], [ mid, 0 ], [ 0, -mid ], [ 0, mid ] ].map do |nx, ny|
          %(<text x="#{nx}" y="#{(ny + size * 0.36).round(2)}" text-anchor="middle" font-size="#{size}" font-weight="600" fill="#{colour}" font-family="#{ShareSvg::FONT}">#{n}</text>)
        end
      end.join
    end

    # A shot's value as a chip, styled as fl-shooters' scorecard chips: an inner ten in
    # the accent, a ten solid, a nine a step paler, anything less only outlined; a shot
    # out of time a red 0.
    def shot_chip(shot, x, y, w, h, font)
      label = set.value_text(shot)
      fill, ink, opacity, stroke = if shot.penalized? then [ MISS, "#ffffff", nil, nil ]
      elsif set.inner_ten?(shot) then [ t.accent, t.on_accent, nil, nil ]
      elsif shot.final_ring.to_i == 10 then [ t.text, t.bg2, 0.94, nil ]
      elsif shot.final_ring.to_i == 9 then [ t.text, t.bg2, 0.62, nil ]
      else [ t.text, t.text, 0.06, true ]
      end
      [ rect(x, y, w, h, fill, rx: h * 0.18, opacity:, stroke: (t.text if stroke), stroke_width: (2 if stroke), stroke_opacity: (0.3 if stroke)),
        text(x + w / 2.0, y + h / 2.0 + font * 0.36, label, font, ink, weight: 700, anchor: "middle") ].join
    end
end
