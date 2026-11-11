# A straightened close-up of a shot (top-down, fixed px/mm, see the engine's
# closeup in docs/engine-events.md) with the position estimates drawn over it:
# blue = what was scored, pink = region centroid, green = circle fit, amber = the
# shooter's call. With `tappable: true` a tap moves the amber mark and fills the
# call form's position (closeup_tap_controller.js).
class CloseupComponent < ApplicationComponent
  COLOURS = { scored: "#2563eb", centroid: "#ec4899", circle_fit: "#16a34a", call: "#f59e0b" }.freeze

  def initialize(shot:, which: :after, tappable: false)
    @shot = shot
    @which = which
    @tappable = tappable
    meta = (shot.estimates || {})["closeup"] || {}
    @cx, @cy = meta["centre"] || [ shot.x_mm.to_f, shot.y_mm.to_f ]
    @ppm = meta["px_per_mm"].to_f
    @size = meta["size_px"].to_i
  end

  def render? = attachment.attached? && @ppm.positive? && @size.positive?

  def attachment = @which == :after ? @shot.closeup_after : @shot.closeup_before

  # mm -> close-up pixel (y up in mm, down in pixels)
  def to_px(x, y) = [ @size / 2.0 + (x - @cx) * @ppm, @size / 2.0 - (y - @cy) * @ppm ]

  def pellet_r_px = TargetSpec::PELLET_MM / 2.0 * @ppm

  def marks
    est = @shot.estimates || {}
    list = []
    list << [ :centroid, *est["centroid"] ] if est["centroid"]
    fit = est["circle_fit"]
    list << [ :circle_fit, fit["x"], fit["y"] ] if fit && fit["x"]
    list << [ :scored, @shot.x_mm, @shot.y_mm ] if @shot.x_mm
    list.map { |kind, x, y| [ kind, *to_px(x, y) ] }
  end

  def call_mark = @shot.call_x_mm ? to_px(@shot.call_x_mm, @shot.call_y_mm) : nil

  def data
    return {} unless @tappable

    { controller: "closeup-tap", "closeup-tap-cx-value": @cx, "closeup-tap-cy-value": @cy,
      "closeup-tap-ppm-value": @ppm, "closeup-tap-size-value": @size, action: "click->closeup-tap#tap" }
  end
end
