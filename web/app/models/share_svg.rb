# The SVG vocabulary of the pictures Spotter posts to CompetitiveShooter.org, after
# fl-shooters' ShareSvg (keep the house rule from there: nothing on a share picture
# is ever cut off with an ellipsis - shrink, wrap, grow, or drop a row into
# "+ N more"). Text widths are estimates that lean wide (SVG cannot measure).
#
# The pictures are drawn as SVG and turned into JPEG by libvips (librsvg), so the
# fonts are whatever fontconfig finds: Helvetica on a Mac, Liberation Sans on a Pi.
module ShareSvg
  FONT = "Helvetica, Arial, 'Liberation Sans', sans-serif".freeze

  module_function

  def esc(value) = ERB::Util.html_escape(value.to_s)

  def text(x, y, content, size, fill, weight: 500, anchor: nil, spacing: nil, opacity: nil)
    attrs = [ %(x="#{r(x)}"), %(y="#{r(y)}"), %(font-family="#{FONT}"), %(font-size="#{r(size)}"), %(font-weight="#{weight}"), %(fill="#{fill}") ]
    attrs << %(text-anchor="#{anchor}") if anchor
    attrs << %(letter-spacing="#{r(spacing)}") if spacing
    attrs << %(fill-opacity="#{opacity}") if opacity
    %(<text #{attrs.join(" ")}>#{esc(content)}</text>)
  end

  # A letter-spaced capitals label, as the share band's eyebrows ("SERIES").
  def eyebrow(x, y, content, size, fill, anchor: nil, opacity: nil)
    text(x, y, content.to_s.upcase, size, fill, weight: 700, anchor:, spacing: size * 0.14, opacity:)
  end

  def text_width(string, size)
    string.to_s.each_char.sum do |c|
      if c == "@" then 1.0
      elsif "ijlt.f!'|,:·".include?(c) then 0.3
      elsif "mwMW".include?(c) then 0.88
      elsif c.match?(/[A-Z]/) then 0.7
      elsif c == " " then 0.3
      else 0.57
      end
    end * size
  end

  # The largest size down from `size` (not below `min`) at which `string` fits on one line.
  def fit_size(string, size, width, min)
    size -= 2 while size > min && text_width(string, size) > width
    size
  end

  # `string` wrapped on its words to `width`: the largest size down to `min_size` that fits in
  # `max_lines`; at the smallest size, as many lines as it takes. [ lines, size ].
  def lines_for(string, size, width, max_lines, min_size)
    size.step(min_size, -2) do |s|
      lines = wrap_words(string, s, width)
      return [ lines, s ] if lines.size <= max_lines
    end
    [ wrap_words(string, min_size, width), min_size ]
  end

  def wrap_words(string, size, width)
    string.to_s.split.each_with_object([ "" ]) do |word, lines|
      candidate = [ lines.last, word ].reject(&:empty?).join(" ")
      text_width(candidate, size) > width && lines.last.present? ? lines << word : lines[-1] = candidate
    end
  end

  def rect(x, y, w, h, fill, rx: 0, opacity: nil, stroke: nil, stroke_width: nil, stroke_opacity: nil)
    attrs = [ %(x="#{r(x)}"), %(y="#{r(y)}"), %(width="#{r(w)}"), %(height="#{r(h)}"), %(fill="#{fill}") ]
    attrs << %(rx="#{r(rx)}") if rx.positive?
    attrs << %(fill-opacity="#{opacity}") if opacity
    attrs << %(stroke="#{stroke}" stroke-width="#{r(stroke_width)}") if stroke
    attrs << %(stroke-opacity="#{stroke_opacity}") if stroke_opacity
    %(<rect #{attrs.join(" ")}/>)
  end

  def r(value) = value.is_a?(Float) ? value.round(2) : value

  # The backdrop every picture shares: the colorway's diagonal gradient, a soft glow in
  # its accent and faint target rings in one corner.
  def backdrop(theme, width, height, rings_at: [ width * 0.86, height * 0.12 ])
    cx, cy = rings_at
    step = width * 0.07
    <<~SVG
      <defs>
        <linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#{theme.bg1}"/><stop offset="1" stop-color="#{theme.bg2}"/></linearGradient>
        <radialGradient id="glow" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#{theme.glow}" stop-opacity="0.35"/><stop offset="1" stop-color="#{theme.glow}" stop-opacity="0"/></radialGradient>
      </defs>
      <rect width="#{width}" height="#{height}" fill="url(#g)"/>
      <circle cx="#{r(cx)}" cy="#{r(cy)}" r="#{r(width * 0.45)}" fill="url(#glow)"/>
      <g fill="none" stroke="#{theme.ring}" stroke-opacity="#{theme.ring_op}" stroke-width="#{r(width * 0.009)}">#{(1..6).map { %(<circle cx="#{r(cx)}" cy="#{r(cy)}" r="#{r(it * step)}"/>) }.join}</g>
    SVG
  end

  # Spotter's mark: a target with a red spot, the size of `size` px, at x, y (its top left).
  def mark(x, y, size)
    k = size / 64.0
    c = ->(v) { r(v * k) }
    <<~SVG
      <g transform="translate(#{r(x)} #{r(y)})">
        <rect width="#{r(size)}" height="#{r(size)}" rx="#{c.(14)}" fill="#1f1f1f" stroke="#ffffff" stroke-opacity="0.3" stroke-width="#{r([ 1.0, size / 32.0 ].max)}"/>
        <circle cx="#{c.(32)}" cy="#{c.(32)}" r="#{c.(21)}" fill="none" stroke="#e7e5e4" stroke-width="#{c.(3.5)}"/>
        <circle cx="#{c.(32)}" cy="#{c.(32)}" r="#{c.(12)}" fill="none" stroke="#e7e5e4" stroke-width="#{c.(3.5)}"/>
        <circle cx="#{c.(37)}" cy="#{c.(28)}" r="#{c.(5.5)}" fill="#ef4444"/>
      </g>
    SVG
  end

  # "Spotter" beside its mark, flush right at `right`, centred on `mid`.
  def brand(right, mid, size, theme)
    label = "Scored by Spotter"
    w = text_width(label, size * 0.6)
    [ text(right, mid + size * 0.21, label, size * 0.6, theme.text, weight: 600, anchor: "end", opacity: 0.9),
      mark(right - w - size * 0.35 - size, mid - size / 2.0, size) ].join
  end

  def document(width, height, body)
    %(<svg xmlns="http://www.w3.org/2000/svg" width="#{r(width)}" height="#{r(height)}" viewBox="0 0 #{r(width)} #{r(height)}">#{body}</svg>)
  end
end
