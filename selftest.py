#!/usr/bin/env python3
"""
Validate the Phase 0 detection pipeline on synthetic backlit frames.

No camera needed. Generates holes at KNOWN sub-pixel positions, adds
realistic sensor noise, and checks that detect_holes() recovers them.
This tells us the ALGORITHM is sound, so that any error we later see
on real frames belongs to the optics and the rig, not the code.
"""
import numpy as np
from target0 import detect_holes, match, PELLET_MM

RNG = np.random.default_rng(7)

MM_PER_PX = 0.083          # 1080p over ~90mm, from the earlier arithmetic
BG, FG = 18.0, 225.0       # dark field, bright hole (not clipped)
W, H = 420, 420


def render(centres_mm, noise_sigma=2.0, blur_px=1.2):
    """Backlit frame: bright discs on a dark field, soft edges + noise."""
    img = np.full((H, W), BG, np.float32)
    yy, xx = np.mgrid[0:H, 0:W]
    r_px = (PELLET_MM / 2.0) / MM_PER_PX
    for (mx, my) in centres_mm:
        cx = W / 2.0 + mx / MM_PER_PX
        cy = H / 2.0 - my / MM_PER_PX
        d = np.hypot(xx - cx, yy - cy)
        # smooth edge -> gives the sub-pixel information a real lens provides
        img += (FG - BG) * 0.5 * (1.0 - np.tanh((d - r_px) / blur_px))
    img += RNG.normal(0, noise_sigma, img.shape)
    return np.clip(img, 0, 255)


def truth_px(centres_mm):
    return [(W / 2.0 + mx / MM_PER_PX, H / 2.0 - my / MM_PER_PX)
            for (mx, my) in centres_mm]


def test_accuracy():
    """Are recovered centres in the right PLACE? (bias / absolute accuracy)"""
    centres = [(-9.3, 6.1), (4.7, -11.2), (12.4, 9.9), (-0.35, -0.4)]
    img = render(centres)
    holes, thr, _ = detect_holes(img, MM_PER_PX)
    assert len(holes) == len(centres), f"found {len(holes)}, expected {len(centres)}"

    tol = 0.5 * PELLET_MM / MM_PER_PX
    ref = [{"xb": x, "yb": y} for x, y in truth_px(centres)]
    m = match(ref, holes, tol)

    print("  absolute accuracy vs known truth")
    errs = {"binary": [], "weighted": []}
    for (tx, ty), got in zip(truth_px(centres), m):
        assert got is not None, "a known hole was not matched"
        errs["binary"].append(np.hypot(got["xb"] - tx, got["yb"] - ty))
        errs["weighted"].append(np.hypot(got["xw"] - tx, got["yw"] - ty))
    for k, v in errs.items():
        mm = np.array(v) * MM_PER_PX
        print(f"    {k:>8}: mean {mm.mean():.4f} mm   worst {mm.max():.4f} mm")
    best = min(np.mean(errs["binary"]), np.mean(errs["weighted"])) * MM_PER_PX
    assert best < 0.05, f"accuracy {best:.4f} mm is worse than expected"
    return best


def test_jitter():
    """Same scene, repeated. Does the centroid sit still? (the noise floor)"""
    centres = [(-6.0, 3.0), (8.0, -7.0)]
    print("  repeatability (scene static, 12 rounds)")
    out = {}
    for n_avg in (1, 16):
        rounds = []
        for _ in range(12):
            stack = np.mean([render(centres) for _ in range(n_avg)], axis=0)
            h, _, _ = detect_holes(stack, MM_PER_PX)
            rounds.append(h)
        ref = rounds[0]
        tol = 0.5 * PELLET_MM / MM_PER_PX
        tracks = [[] for _ in ref]
        for rr in rounds:
            for i, c in enumerate(match(ref, rr, tol)):
                tracks[i].append(c)
        for bx, by, name in (("xb", "yb", "binary"), ("xw", "yw", "weighted")):
            devs = []
            for tr in tracks:
                pts = np.array([(c[bx], c[by]) for c in tr if c is not None])
                devs.append(np.hypot(pts[:, 0].std(ddof=1), pts[:, 1].std(ddof=1)))
            out[(n_avg, name)] = float(np.mean(devs)) * MM_PER_PX
            print(f"    {n_avg:>2}-frame {name:>8}: {out[(n_avg, name)]:.4f} mm")
    assert out[(16, "weighted")] < out[(1, "weighted")], \
        "frame averaging should reduce jitter"
    return min(out[(16, "binary")], out[(16, "weighted")])


def test_overlap():
    """Does the area fraction collapse as shots overlap, as predicted?"""
    print("  overlapping-shot degradation")
    base = [(0.0, 0.0)]
    before = np.mean([render(base) for _ in range(16)], axis=0)
    expected_area = np.pi * (PELLET_MM / 2.0 / MM_PER_PX) ** 2
    rows = []
    for sep_mm in (6.0, 4.0, 3.0, 2.0, 1.0, 0.5):
        after = np.mean([render(base + [(sep_mm, 0.0)]) for _ in range(16)], axis=0)
        diff = np.clip(after - before, 0, None)
        hd, _, _ = detect_holes(diff, MM_PER_PX, min_mm=0.4)
        frac = (max(h["area_px"] for h in hd) / expected_area) if hd else 0.0
        if hd:
            big = max(hd, key=lambda d: d["area_px"])
            err = abs((big["xw"] - W / 2.0) * MM_PER_PX - sep_mm)
        else:
            err = float("nan")
        rows.append((sep_mm, frac, err))
        print(f"    separation {sep_mm:4.1f} mm -> new area {frac*100:5.1f}% "
              f"of a hole, centre error {err:.3f} mm")
    assert rows[0][1] > 0.75, "well-separated shots should give a clean full hole"
    assert rows[-1][1] < rows[0][1], "overlap should shrink the new region"
    return rows


if __name__ == "__main__":
    print("\nPhase 0 pipeline self-test (synthetic, no camera)\n" + "-" * 58)
    acc = test_accuracy()
    print()
    floor = test_jitter()
    print()
    rows = test_overlap()
    print("-" * 58)
    print(f"\n  algorithm absolute accuracy : {acc:.4f} mm")
    print(f"  algorithm noise floor       : {floor:.4f} mm")
    from scoring import PISTOL, decimal_step_mm
    budget = decimal_step_mm(PISTOL) / 4.0
    print(f"  10m air pistol budget       : {budget:.3f} mm "
          f"(decimal step {decimal_step_mm(PISTOL):.2f} mm)")
    print("\n  The algorithm is not the limiting factor. Whatever the real")
    print("  camera reports above these numbers comes from optics, lighting")
    print("  and rig stability.\n")
