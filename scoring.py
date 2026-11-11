#!/usr/bin/env python3
"""
ISSF ring geometry and score computation. Pure maths - no camera, no OpenCV.

Scoring convention (ISSF): a shot takes the higher value if the pellet HOLE
TOUCHES the ring line, so we score the edge of the hole nearest the centre:

    r_edge = r_centre - pellet_radius

Ring diameters follow  d(n) = d10 + (10 - n) * step_d.

  10m Air Pistol: d10 = 11.5mm, step 16mm  -> ring 7 = 59.5mm = the BLACK
                  aiming mark, ring 1 = 155.5mm, card 170mm.
  10m Air Rifle : d10 =  0.5mm, step  5mm  -> ring 4 = 30.5mm = the BLACK,
                  ring 1 = 45.5mm, card 80mm.

Decimal scoring is piecewise. Outside the 10-ring each ring divides into ten
bands of (step_radius / 10). Inside the 10-ring the DISC divides into ten
bands, so dead centre reads 10.9 - which is why the 10-ring cannot simply be
treated as another annulus.
"""
from dataclasses import dataclass

PELLET_MM = 4.5  # .177


@dataclass(frozen=True)
class TargetSpec:
    name: str
    ten_dia_mm: float
    step_dia_mm: float        # DIAMETER increase per ring outward
    black_ring: int           # which ring is the edge of the aiming mark
    inner_ten_dia_mm: float
    max_decimal: float = 10.9

    @property
    def ten_radius_mm(self):
        return self.ten_dia_mm / 2.0

    @property
    def step_mm(self):        # RADIUS step
        return self.step_dia_mm / 2.0

    @property
    def black_dia_mm(self):
        return ring_dia_mm(self, self.black_ring)

    @property
    def inner_ten_radius_mm(self):
        return self.inner_ten_dia_mm / 2.0


PISTOL = TargetSpec("10m Air Pistol", 11.5, 16.0, 7, 5.0)
RIFLE = TargetSpec("10m Air Rifle", 0.5, 5.0, 4, 0.5)
SPECS = {"pistol": PISTOL, "rifle": RIFLE}


def ring_dia_mm(spec: TargetSpec, ring: int) -> float:
    return spec.ten_dia_mm + (10 - ring) * spec.step_dia_mm


def ring_radius_mm(spec: TargetSpec, ring: int) -> float:
    return ring_dia_mm(spec, ring) / 2.0


def decimal_step_mm(spec: TargetSpec) -> float:
    """Radius change per 0.1 of score, outside the 10-ring."""
    return spec.step_mm / 10.0


def score(r_mm: float, spec: TargetSpec = PISTOL, pellet_mm: float = PELLET_MM):
    r_edge = max(0.0, r_mm - pellet_mm / 2.0)
    ten_r = spec.ten_radius_mm

    if r_edge <= ten_r:
        # inside the ten: 10.0 at the ring edge rising to 10.9 at centre
        decimal = 10.0 + 0.9 * (ten_r - r_edge) / ten_r
        integer = 10
    else:
        decimal = 10.0 - (r_edge - ten_r) / spec.step_mm
        steps = (r_edge - ten_r) / spec.step_mm
        integer = max(0, 10 - int(-(-steps // 1)))  # ceil

    decimal = max(0.0, min(decimal, spec.max_decimal))
    return {
        "decimal": round(decimal, 1),
        "integer": integer,
        "inner_ten": r_edge <= spec.inner_ten_radius_mm,
        "r_mm": r_mm,
        "r_edge_mm": r_edge,
    }


def score_xy(x_mm: float, y_mm: float, spec: TargetSpec = PISTOL, **kw):
    out = score((x_mm * x_mm + y_mm * y_mm) ** 0.5, spec, **kw)
    out["x_mm"], out["y_mm"] = x_mm, y_mm
    return out


if __name__ == "__main__":
    for spec in (PISTOL, RIFLE):
        print(f"\n{spec.name}  (black = ring {spec.black_ring} = "
              f"{spec.black_dia_mm}mm, decimal step {decimal_step_mm(spec):.2f}mm)")
        print("  ring   dia mm   radius mm")
        for ring in range(10, 0, -1):
            mark = "   <- BLACK" if ring == spec.black_ring else ""
            print(f"   {ring:>2}   {ring_dia_mm(spec, ring):6.1f}   "
                  f"{ring_radius_mm(spec, ring):7.2f}{mark}")

    print("\n10m Air Pistol scoring checks")
    for r, label in [
        (0.0, "dead centre"),
        (PISTOL.ten_radius_mm + PELLET_MM / 2, "edge touches 10 ring"),
        (ring_radius_mm(PISTOL, 9) + PELLET_MM / 2, "edge touches 9 ring"),
        (ring_radius_mm(PISTOL, 7) + PELLET_MM / 2, "edge touches 7 ring (black edge)"),
        (ring_radius_mm(PISTOL, 1) + PELLET_MM / 2, "edge touches 1 ring"),
    ]:
        s = score(r, PISTOL)
        tag = "  INNER TEN" if s["inner_ten"] else ""
        print(f"  r={r:6.2f}mm -> {s['decimal']:>4.1f} decimal / "
              f"{s['integer']:>2} ring   ({label}){tag}")
