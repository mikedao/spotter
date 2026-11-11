# ISSF 10 m ring geometry and scoring, ported from the engine's scoring.py (the two
# must agree: spec/models/target_spec_spec.rb pins the same reference values as
# scoring.py's own checks).
#
# Ring diameters follow d(n) = d10 + (10 - n) * step. Air pistol steps 16 mm in
# DIAMETER (not 8): its black is ring 7 = 59.5 mm, ring 1 = 155.5 mm.
#
# Decimals are piecewise and TRUNCATED (as freETarget and electronic scoring do):
# outside the 10 each ring is ten bands of step/10 in radius; inside the 10 the disc
# is ten bands, so dead centre reads 10.9.
#
# A hole touches a line by its edge nearest the centre: r_edge = r - mark / 2.
# `mark_mm` is the pellet's mark - 4.5 mm for the official gauge, PELLET_MARK_MM
# (5.8) for the "pellet" rule the engine defaults to, which matched the shooter's
# own calls 29 of 30 (see the engine's CLAUDE.md).
class TargetSpec
  PELLET_MM = 4.5
  PELLET_MARK_MM = 5.8

  Spec = Data.define(:key, :name, :ten_dia_mm, :step_dia_mm, :black_ring, :inner_ten_dia_mm, :card_mm)

  SPECS = {
    "pistol" => Spec.new(key: "pistol", name: "10m Air Pistol", ten_dia_mm: 11.5, step_dia_mm: 16.0,
                         black_ring: 7, inner_ten_dia_mm: 5.0, card_mm: 170.0),
    "rifle" => Spec.new(key: "rifle", name: "10m Air Rifle", ten_dia_mm: 0.5, step_dia_mm: 5.0,
                        black_ring: 4, inner_ten_dia_mm: 0.5, card_mm: 80.0)
  }.freeze

  Score = Data.define(:decimal, :ring, :inner_ten, :r_edge_mm)

  def self.fetch(key) = new(SPECS.fetch(key.to_s))

  attr_reader :spec
  delegate :key, :name, :black_ring, :card_mm, to: :spec

  def initialize(spec) = @spec = spec

  def ring_radius_mm(ring) = (spec.ten_dia_mm + (10 - ring) * spec.step_dia_mm) / 2.0
  def black_radius_mm = ring_radius_mm(black_ring)
  def inner_ten_radius_mm = spec.inner_ten_dia_mm / 2.0
  def step_mm = spec.step_dia_mm / 2.0

  # Score a hole whose centre is r_mm from the target centre.
  def score(r_mm, mark_mm: PELLET_MARK_MM)
    r_edge = [ r_mm - mark_mm / 2.0, 0.0 ].max
    ten_r = ring_radius_mm(10)
    if r_edge <= ten_r
      decimal = 10.0 + 0.9 * (ten_r - r_edge) / ten_r
      ring = 10
    else
      steps = (r_edge - ten_r) / step_mm
      decimal = 10.0 - steps
      ring = [ 0, 10 - steps.ceil ].max
    end
    decimal = decimal.clamp(0.0, 10.9)
    decimal = (decimal * 10.0 + 1e-9).floor / 10.0
    Score.new(decimal:, ring:, inner_ten: r_edge <= inner_ten_radius_mm, r_edge_mm: r_edge)
  end

  def score_xy(x_mm, y_mm, **) = score(Math.hypot(x_mm, y_mm), **)

  # Where a point is from the centre, in a shooter's words (as the engine says it).
  DIRECTIONS = [ "right", "high right", "high", "high left", "left", "low left", "low", "low right" ].freeze

  def self.direction(x_mm, y_mm, inner_ten: false)
    return "centre" if inner_ten || Math.hypot(x_mm, y_mm) < 1.0

    angle = Math.atan2(y_mm, x_mm) * 180.0 / Math::PI % 360.0
    DIRECTIONS[(((angle + 22.5) % 360.0) / 45.0).floor]
  end
end
