#!/usr/bin/env python3
"""
Validate the Phase 0 detection pipeline on synthetic backlit frames.

No camera needed. Generates holes at KNOWN sub-pixel positions, adds
realistic sensor noise, and checks that detect_holes() recovers them.
This tells us the ALGORITHM is sound, so that any error we later see
on real frames belongs to the optics and the rig, not the code.
"""
import numpy as np
from target0 import detect_holes, match, fit_pellet, PELLET_MM

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


def _to_mm(px, py):
    return ((np.asarray(px) - W / 2.0) * MM_PER_PX,
            -(np.asarray(py) - H / 2.0) * MM_PER_PX)


def test_overlap():
    """
    Overlapping shot: only a crescent is new. Centroid vs known-radius circle
    fit, against the true centre of the new pellet.
    """
    print("  overlapping-shot degradation   (centroid -> circle fit)")
    base = [(0.0, 0.0)]
    before = np.mean([render(base) for _ in range(16)], axis=0)
    expected_area = np.pi * (PELLET_MM / 2.0 / MM_PER_PX) ** 2
    rows = []
    for sep_mm in (6.0, 4.0, 3.0, 2.0, 1.0, 0.5):
        after = np.mean([render(base + [(sep_mm, 0.0)]) for _ in range(16)], axis=0)
        diff = np.clip(after - before, 0, None)
        hd, _, _ = detect_holes(diff, MM_PER_PX, min_mm=0.4)
        frac, err, ferr, arc = 0.0, float("nan"), float("nan"), 0.0
        if hd:
            big = max(hd, key=lambda d: d["area_px"])
            frac = big["area_px"] / expected_area
            err = np.hypot((big["xw"] - W / 2.0) * MM_PER_PX - sep_mm,
                           (big["yw"] - H / 2.0) * MM_PER_PX)
            f = fit_pellet(diff, big, _to_mm)
            if f["ok"]:
                ferr = np.hypot(f["x_mm"] - sep_mm, f["y_mm"])
                arc = f["arc_deg"]
        rows.append((sep_mm, frac, err, ferr))
        fit_s = (f"{ferr:.3f} mm ({arc:3.0f} deg of arc)" if np.isfinite(ferr)
                 else "no round arc - falls back to centroid")
        print(f"    separation {sep_mm:4.1f} mm -> new area {frac*100:5.1f}%, "
              f"centre error {err:.3f} -> {fit_s}")
    assert rows[0][1] > 0.75, "well-separated shots should give a clean full hole"
    assert rows[-1][1] < rows[0][1], "overlap should shrink the new region"
    for sep, _, err, ferr in rows:
        if sep >= 2.0:
            assert np.isfinite(ferr) and ferr < 0.1, \
                f"circle fit at {sep} mm separation: {ferr:.3f} mm"
    return rows


def test_torn():
    """
    Paper tears: the visible region is the pellet hole plus a flap ripped
    along one direction. The centroid is dragged along the tear; the circle
    fit should stay on the pellet.
    """
    print("  torn paper (hole + flap ripped toward the centre)")
    yy, xx = np.mgrid[0:H, 0:W]
    out = []
    for flap_mm, ang_deg in ((3.0, 0), (5.0, 30), (7.0, 200)):
        img = np.full((H, W), BG, np.float32)
        r_px = (PELLET_MM / 2.0) / MM_PER_PX
        d = np.hypot(xx - W / 2.0, yy - H / 2.0)
        disc = 0.5 * (1.0 - np.tanh((d - r_px) / 1.2))
        # flap: a ragged wedge from the hole edge outward
        t = np.radians(ang_deg)
        u = ((xx - W / 2.0) * np.cos(t) - (yy - H / 2.0) * np.sin(t)) * MM_PER_PX
        v = ((xx - W / 2.0) * np.sin(t) + (yy - H / 2.0) * np.cos(t)) * MM_PER_PX
        half = 1.6 * (1 - np.clip(u / (PELLET_MM / 2 + flap_mm), 0, 1)) \
            + 0.25 * np.sin(u * 7.0)
        flap = ((u > 0) & (u < PELLET_MM / 2 + flap_mm) &
                (np.abs(v) < half)).astype(np.float32)
        flap = np.asarray(__import__("cv2").GaussianBlur(flap, (0, 0), 1.2))
        img += (FG - BG) * np.maximum(disc, flap)
        img += RNG.normal(0, 2.0, img.shape)
        hd, _, _ = detect_holes(np.clip(img, 0, 255), MM_PER_PX,
                                min_circularity=0.3)
        big = max(hd, key=lambda h: h["area_px"])
        cerr = np.hypot((big["xw"] - W / 2.0), (big["yw"] - H / 2.0)) * MM_PER_PX
        f = fit_pellet(img, big, _to_mm)
        ferr = np.hypot(f["x_mm"], f["y_mm"]) if f["ok"] else float("nan")
        out.append(ferr)
        print(f"    {flap_mm:.0f} mm flap at {ang_deg:3d} deg: centroid off "
              f"{cerr:.3f} mm -> circle fit {ferr:.3f} mm "
              f"({f['arc_deg']:.0f} deg of arc)")
        assert np.isfinite(ferr) and ferr < 0.1, f"torn hole fit {ferr:.3f} mm"
    return max(out)


def render_card(tilt_deg, D_mm=247.0, holes_mm=(), k1=-0.185, k2=0.293,
                card_offset_mm=(20.0, -15.0), W_=1920, H_=1080, f_px=1371.0,
                noise_sigma=2.0):
    """
    A pistol card seen by a pinhole camera rotated tilt_deg off to the side,
    through a wide-angle lens with the radial distortion measured on the real
    Kiyo. Returns (image, true_centre_px, world_to_image) so results can be
    checked against exact truth.

    Every pixel is traced lens -> ray -> card plane, so perspective and
    distortion are exact, not approximated by the model under test.
    """
    from scoring import PISTOL, ring_radius_mm
    t = np.radians(tilt_deg)
    ex = np.array([np.cos(t), 0.0, np.sin(t)])     # card +x in camera coords
    ey = np.array([0.0, -1.0, 0.0])                # card +y (up)
    C = np.array([card_offset_mm[0], -card_offset_mm[1], D_mm])
    n = np.cross(ex, ey)
    dist = (W_ / 2.0, H_ / 2.0, W_ / 2.0)

    def undistort(px, py):
        u, v = (px - dist[0]) / dist[2], (py - dist[1]) / dist[2]
        r2 = u * u + v * v
        s = 1 + k1 * r2 + k2 * r2 * r2
        return dist[0] + u * s * dist[2], dist[1] + v * s * dist[2]

    yy, xx = np.mgrid[0:H_, 0:W_].astype(np.float64)
    ux, uy = undistort(xx, yy)
    d = np.stack([(ux - W_ / 2) / f_px, (uy - H_ / 2) / f_px,
                  np.ones_like(ux)], -1)
    tt = (n @ C) / (d @ n)
    P = d * tt[..., None] - C
    X, Y = P @ ex, P @ ey

    gy_x, gx_x = np.gradient(X)
    gy_y, gx_y = np.gradient(Y)
    pix = np.sqrt(np.abs(gx_x * gy_y - gy_x * gx_y))   # mm per pixel, local
    s = 0.6 * pix

    def cover(r, lo, hi):
        return 0.5 * (np.tanh((r - lo) / s) - np.tanh((r - hi) / s))

    r = np.hypot(X, Y)
    PAPER, INK = 200.0, 25.0
    Rb = ring_radius_mm(PISTOL, PISTOL.black_ring)
    img = INK + (PAPER - INK) * 0.5 * (1 + np.tanh((r - Rb) / s))
    lw = 0.2
    for ring in range(1, 11):
        R = ring_radius_mm(PISTOL, ring)
        if ring < PISTOL.black_ring:
            img -= (PAPER - INK) * cover(r, R - lw, R)
        elif ring > PISTOL.black_ring:
            img += (PAPER - INK) * cover(r, R - lw, R)
    Ri = PISTOL.inner_ten_radius_mm
    img += (PAPER - INK) * cover(r, Ri - lw, Ri)
    img = np.clip(img, INK, PAPER)
    for hx, hy in holes_mm:
        dh = np.hypot(X - hx, Y - hy)
        img = np.maximum(img, 235.0 * 0.5 * (1 - np.tanh((dh - 2.25) / s)))
    off = (np.abs(X) > 85) | (np.abs(Y) > 85)
    img[off] = 40.0
    img *= 1.0 - 0.15 * (xx / W_)                   # mild lighting gradient
    img += RNG.normal(0, noise_sigma, img.shape)

    def w2i(x, y):
        """target mm -> distorted image px, by Newton on the forward trace."""
        p = C + x * ex + y * ey
        u0 = f_px * p[0] / p[2] + W_ / 2
        v0 = f_px * p[1] / p[2] + H_ / 2
        px, py = u0, v0
        for _ in range(30):
            a, b = undistort(px, py)
            px, py = px + (u0 - a), py + (v0 - b)
        return px, py

    return np.clip(img, 0, 255).astype(np.float32), w2i


def test_dark_surround():
    """
    The card inside a dark surround that rings it completely (the 2026-11-12
    Pi rig): the surround must never be taken for the aiming mark. Its outer
    contour encloses the whole card, so counted solid it passed as a huge
    round "mark" - whenever its hull had 5+ points (here: a bright corner).
    """
    import math
    from geometry import find_target_frame
    img, w2i = render_card(30.0, D_mm=340.0)    # back far enough for the whole card
    H, W = img.shape
    yy, xx = np.mgrid[0:H, 0:W]
    img[(xx + yy) < 160] = 200.0                # a lit corner: the hull is a pentagon
    tf, diag = find_target_frame(img)
    assert tf is not None, f"dark surround: no mark found ({diag.get('reason')})"
    tx, ty = w2i(0.0, 0.0)
    err = math.hypot(tf.cx - tx, tf.cy - ty)
    print(f"  dark surround ringing the card: mark found {err:.1f} px from the true centre")
    assert err < 15, f"dark surround taken for the aiming mark ({err:.0f} px off)"
    return err


def test_perspective():
    """
    Camera off to the side: is the scored position right?

    Holes at known places on a rendered card; compare the radius the full
    pipeline reports against truth. Radius is what scores, and it does not
    depend on the unobservable in-plane rotation.
    """
    import math
    from scoring import PISTOL
    from phase1 import establish
    from geometry import refine_bull_ellipse, find_target_frame, \
        flatten_illumination
    # mid-band radii, clear of printed lines: this test is about geometry,
    # and a hole merged with a ring line is a separate detector limitation
    holes = [(r * math.cos(math.radians(a)), r * math.sin(math.radians(a)))
             for r, a in ((9.75, 30), (17.75, 200), (25.75, 300),
                          (41.75, 120), (57.75, 340), (73.75, 250))]
    print("  camera off to the side (perspective + Kiyo lens distortion)")
    print("     angle   model        centre err   worst radius err   "
          "ellipse-only worst")
    worst_all = 0.0
    for tilt in (0, 20, 37, 45):
        img, w2i = render_card(tilt, holes_mm=holes)
        tf, info = establish(img, PISTOL, verbose=False)
        assert tf is not None and info.get("perspective"), \
            f"{tilt} deg: perspective fit failed: {info.get('reason')}"
        flat, _ = flatten_illumination(np.clip(img, 0, 255).astype(np.uint8))
        tf_e, _ = refine_bull_ellipse(flat, find_target_frame(img)[0])

        cxe = math.hypot(*tf.to_mm(*w2i(0.0, 0.0)))
        # difference against the bare card, as `shot` does: a static scan
        # merges holes with the white ring lines inside the black
        bare, _ = render_card(tilt)
        found = detect_holes(np.clip(img - bare, 0, None), tf.mm_per_px)[0]
        errs, errs_e = [], []
        for hx, hy in holes:
            px, py = w2i(hx, hy)
            h = min(found, key=lambda g: math.hypot(g["xw"] - px, g["yw"] - py))
            assert math.hypot(h["xw"] - px, h["yw"] - py) < 5, \
                f"{tilt} deg: hole at ({hx:.1f},{hy:.1f}) not detected"
            rt = math.hypot(hx, hy)
            errs.append(abs(tf.radius_mm(h["xw"], h["yw"]) - rt))
            errs_e.append(abs(tf_e.radius_mm(h["xw"], h["yw"]) - rt))
        worst_all = max(worst_all, max(errs), cxe)
        print(f"     {tilt:>3} deg  {len(info['rings']):>2} rings     "
              f"{cxe:.3f} mm      {max(errs):.3f} mm           "
              f"{max(errs_e):.2f} mm")
    budget = 0.2
    assert worst_all < budget / 2, \
        f"off-axis error {worst_all:.3f} mm uses over half the budget"
    return worst_all


if __name__ == "__main__":
    print("\nPhase 0 pipeline self-test (synthetic, no camera)\n" + "-" * 58)
    acc = test_accuracy()
    print()
    floor = test_jitter()
    print()
    rows = test_overlap()
    print()
    torn = test_torn()
    print()
    persp = test_perspective()
    print()
    test_dark_surround()
    print("-" * 58)
    print(f"\n  off-axis geometry worst     : {persp:.4f} mm")
    print(f"\n  algorithm absolute accuracy : {acc:.4f} mm")
    print(f"  algorithm noise floor       : {floor:.4f} mm")
    from scoring import PISTOL, decimal_step_mm
    budget = decimal_step_mm(PISTOL) / 4.0
    print(f"  10m air pistol budget       : {budget:.3f} mm "
          f"(decimal step {decimal_step_mm(PISTOL):.2f} mm)")
    print("\n  The algorithm is not the limiting factor. Whatever the real")
    print("  camera reports above these numbers comes from optics, lighting")
    print("  and rig stability.\n")
