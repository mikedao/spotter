#!/usr/bin/env python3
"""
Phase 1 - locate the target from the target itself, and score shots.

The key difference from Phase 0: there is no fixed pixel->mm calibration.
Centre and scale are re-derived from the card's own black aiming mark in every
frame, so camera drift, thermal creep and mount settling cancel out entirely.

    ./phase1.py locate                 # show the derived geometry
    ./phase1.py score                  # find holes and score them
    ./phase1.py shot                   # before/after: score the NEW hole
    ./phase1.py locate --image out/snap_raw.png     # work from a file
"""
import argparse
import sys
from pathlib import Path

import cv2
import numpy as np

import target0
from geometry import (find_target_frame, refine_bull_ellipse,
                      flatten_illumination, draw_rings)
from scoring import SPECS, PISTOL, score_xy, decimal_step_mm

HERE = Path(__file__).resolve().parent
OUT = HERE / "out"


def acquire(a):
    """Grab a frame from the camera, or load one from disk."""
    if a.image:
        g = cv2.imread(a.image, cv2.IMREAD_GRAYSCALE)
        if g is None:
            sys.exit(f"could not read {a.image}")
        return g.astype(np.float32)

    # Phase 1 does NOT need calib.json. Geometry comes from the target itself.
    # The full frame is used by default; --roi opts back in to the saved crop,
    # which is only ever useful for excluding background clutter. A stale ROI
    # from an earlier camera position will silently clip the card, so it is no
    # longer the default.
    roi, dev, w, h = None, a.device, 1920, 1080
    if a.roi:
        try:
            cal = target0.load_calib()
            roi, dev = cal["roi"], cal.get("device", a.device)
            w, h = cal["width"], cal["height"]
        except SystemExit:
            print("  --roi given but no calib.json; using the full frame")

    cap = target0.open_camera(dev, w, h)
    gray, _ = target0.grab_gray(cap, a.frames)
    cap.release()
    return target0.crop(gray, roi) if roi else gray


def establish(gray, spec, verbose=True):
    """Find and refine the target frame. Returns (TargetFrame, info)."""
    flat, _ = flatten_illumination(np.clip(gray, 0, 255).astype(np.uint8))
    tf0, diag = find_target_frame(gray, black_dia_mm=spec.black_dia_mm)
    if tf0 is None:
        print(f"  could not find the aiming mark: {diag.get('reason')}")
        return None, diag
    tf, info = refine_bull_ellipse(flat, tf0)
    if verbose:
        print(f"  aiming mark : ring {spec.black_ring} = {spec.black_dia_mm} mm")
        print(f"  centre      : ({tf.cx:.2f}, {tf.cy:.2f}) px")
        print(f"  semi-axes   : {tf.semi_a:.2f} x {tf.semi_b:.2f} px "
              f"at {tf.angle_deg:.1f} deg")
        print(f"  axis ratio  : {tf.axis_ratio:.4f}"
              f"  -> implied tilt {tf.tilt_deg:.1f} deg")
        print(f"  scale       : {tf.mm_per_px:.5f} mm/px "
              f"({1/tf.mm_per_px:.1f} px/mm)")
        if info.get("refined"):
            print(f"  edge fit    : {info['edge_points']} points, "
                  f"RMS {info['edge_rms_px']:.2f} px")
        else:
            print(f"  edge fit    : NOT applied ({info.get('reason')})")
        r1_mm = 77.75 if spec is not None and spec.name.startswith("10m Air Pistol") else None
        from scoring import ring_radius_mm as _rr
        r1_px = _rr(spec, 1) / tf.mm_per_px
        H, W = gray.shape[:2]
        over = [n for n, v in (("left", tf.cx - r1_px), ("top", tf.cy - r1_px),
                               ("right", W - (tf.cx + r1_px)),
                               ("bottom", H - (tf.cy + r1_px))) if v < 0]
        if over:
            print(f"\n  ! The ring-1 scoring edge runs outside the frame on the "
                  f"{', '.join(over)}.")
            print("    Shots landing there cannot be seen. Recentre the card.")
        if tf.axis_ratio < 0.98:
            print(f"\n  ! The aiming mark is {(1/tf.axis_ratio-1)*100:.0f}% "
                  f"out of round. Either the camera is off-axis or the")
            print("    sensor pixels are not square. Square the camera up and")
            print("    re-run: if the ratio goes to ~1.000 it was tilt.")
            print("    Perspective is projective; this affine model only")
            print("    corrects it to first order.")
    return tf, info


def report(holes, tf, spec, vis=None, quiet=False):
    rows = []
    for h in holes:
        x_mm, y_mm = tf.to_mm(h["xw"], h["yw"])
        s = score_xy(x_mm, y_mm, spec)
        s["clipped"] = h.get("clipped", False)
        s["dia_mm"] = h["diam_px"] * tf.mm_per_px
        s["circ"] = h["circ"]
        rows.append(s)
        if vis is not None:
            c = (int(round(h["xw"])), int(round(h["yw"])))
            cv2.drawMarker(vis, c, (255, 0, 255), cv2.MARKER_TILTED_CROSS, 25, 2)
            cv2.putText(vis, f"{s['decimal']}", (c[0] + 18, c[1] - 10),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.9, (255, 0, 255), 2)
    if quiet:
        return rows
    if not rows:
        print("  no holes detected")
        return rows
    print(f"\n  {'#':>2} {'x mm':>8} {'y mm':>8} {'r mm':>8} "
          f"{'score':>6} {'ring':>5} {'dia mm':>7} {'circ':>5}")
    print("  " + "-" * 60)
    for i, s in enumerate(rows):
        flag = ""
        if s["inner_ten"]:
            flag += "  INNER TEN"
        if s["clipped"]:
            flag += "  EDGE-CLIPPED"
        print(f"  {i:>2} {s['x_mm']:>+8.2f} {s['y_mm']:>+8.2f} {s['r_mm']:>8.2f} "
              f"{s['decimal']:>6.1f} {s['integer']:>5} {s['dia_mm']:>7.2f} "
              f"{s['circ']:>5.2f}{flag}")
    return rows


def cmd_locate(a):
    spec = SPECS[a.target]
    gray = acquire(a)
    print(f"\n{spec.name}")
    tf, _ = establish(gray, spec)
    if tf is None:
        return
    vis = cv2.cvtColor(np.clip(gray, 0, 255).astype(np.uint8), cv2.COLOR_GRAY2BGR)
    draw_rings(vis, tf, spec)
    OUT.mkdir(exist_ok=True)
    cv2.imwrite(str(OUT / "p1_locate.png"), vis)
    print(f"\n  overlay -> {OUT/'p1_locate.png'}")
    print("  Check the yellow rings sit on the printed ones.\n")


def cmd_score(a):
    spec = SPECS[a.target]
    gray = acquire(a)
    print(f"\n{spec.name}")
    tf, _ = establish(gray, spec)
    if tf is None:
        return
    holes, _, _ = target0.detect_holes(gray, tf.mm_per_px, max_holes=a.expect)
    vis = cv2.cvtColor(np.clip(gray, 0, 255).astype(np.uint8), cv2.COLOR_GRAY2BGR)
    draw_rings(vis, tf, spec)
    rows = report(holes, tf, spec, vis)
    OUT.mkdir(exist_ok=True)
    cv2.imwrite(str(OUT / "p1_score.png"), vis)
    if rows:
        tot = sum(r["integer"] for r in rows)
        dec = sum(r["decimal"] for r in rows)
        print(f"\n  total: {tot} rings / {dec:.1f} decimal over {len(rows)} shot(s)")
    print(f"  overlay -> {OUT/'p1_score.png'}\n")


def cmd_shot(a):
    """
    Baseline, then a new shot. Scores only what changed.

    The two captures are REGISTERED through the target itself before being
    differenced. Without that, any camera movement between them turns every
    printed ring line into a bright edge in the difference image, and you get
    dozens of phantom "shots" spaced exactly one ring apart.
    """
    from geometry import align_matrix, frame_shift_mm

    spec = SPECS[a.target]
    input("\nBASELINE: leave the card as-is and press ENTER...")
    before = acquire(a)
    tf_b, _ = establish(before, spec, verbose=False)
    if tf_b is None:
        sys.exit("  could not locate the target in the baseline frame")
    hb, _, _ = target0.detect_holes(before, tf_b.mm_per_px)
    print(f"  baseline: {len(hb)} hole(s) on the card")

    input("Now ADD A SHOT, then press ENTER...")
    after = acquire(a)
    print(f"\n{spec.name}")
    tf, _ = establish(after, spec)
    if tf is None:
        return

    # --- register the baseline into the new frame's geometry ------------
    moved_mm, scale_pct = frame_shift_mm(tf_b, tf)
    M = align_matrix(tf_b, tf, after.shape)
    # WARP_INVERSE_MAP is essential: M already maps AFTER coordinates back to
    # BEFORE coordinates, which is exactly the inverse map warpAffine wants.
    # Without the flag OpenCV treats M as a forward map and doubles the error.
    before_reg = cv2.warpAffine(
        before.astype(np.float32), M, (after.shape[1], after.shape[0]),
        flags=cv2.INTER_LINEAR | cv2.WARP_INVERSE_MAP,
        borderMode=cv2.BORDER_REPLICATE)

    print(f"\n  camera moved {moved_mm:.2f} mm between captures "
          f"(scale change {scale_pct:+.2f}%)")
    if moved_mm > 1.0:
        print("  -> registered through the target, so this is corrected.")
    if moved_mm > 25.0:
        print("  ! That is a large move. If the card itself was disturbed, the")
        print("    difference is meaningless - redo the baseline.")

    diff = np.clip(after.astype(np.float32) - before_reg, 0, None)

    # Filters matter here. A new region must be hole-SIZED; a crescent from an
    # overlapping shot is not round, so circularity is kept permissive but not
    # disabled, or registration residue floods the list.
    hd, _, _ = target0.detect_holes(diff, tf.mm_per_px, min_mm=2.0,
                                    min_circularity=0.30, max_holes=a.expect)
    hd.sort(key=lambda h: h["area_px"], reverse=True)

    OUT.mkdir(exist_ok=True)
    cv2.imwrite(str(OUT / "p1_shot_diff.png"),
                np.clip(diff * 3, 0, 255).astype(np.uint8))

    if not hd:
        print("\n  No new region found. Was a shot actually added?")
        return

    ref = float(np.median([h["area_px"] for h in hb])) if hb else None
    print(f"\n  NEW region(s), largest first"
          f"{'  (hole area ref from baseline)' if ref else ''}:")
    vis = cv2.cvtColor(np.clip(after, 0, 255).astype(np.uint8), cv2.COLOR_GRAY2BGR)
    draw_rings(vis, tf, spec)
    rows = report(hd, tf, spec, vis)

    for i, h in enumerate(hd):
        if ref:
            frac = h["area_px"] / ref
            verdict = ("clean" if frac > 0.75 else
                       "PARTIAL - overlaps an existing hole" if frac > 0.15
                       else "sliver - position unreliable")
            print(f"    [{i}] {frac*100:5.1f}% of a full hole -> {verdict}")

    best = rows[0]
    print(f"\n  SHOT: {best['decimal']} decimal / ring {best['integer']}"
          f"   at x {best['x_mm']:+.2f} mm  y {best['y_mm']:+.2f} mm"
          + ("   INNER TEN" if best["inner_ten"] else ""))
    if len(hd) > 1:
        print(f"  ({len(hd)-1} smaller region(s) also found - if those are not")
        print("   real shots, pass --expect 1)")
    cv2.imwrite(str(OUT / "p1_shot.png"), vis)
    print(f"\n  overlay -> {OUT/'p1_shot.png'}")
    print(f"  difference image -> {OUT/'p1_shot_diff.png'}\n")


def _scale_tf(tf, k):
    """Rescale a TargetFrame found on a downscaled image back to full size."""
    from geometry import TargetFrame
    return TargetFrame(cx=tf.cx * k, cy=tf.cy * k, semi_a=tf.semi_a * k,
                       semi_b=tf.semi_b * k, angle_deg=tf.angle_deg,
                       black_dia_mm=tf.black_dia_mm, area_px=tf.area_px * k * k,
                       circularity=tf.circularity)


def _hud(img, lines, x=12, y=28, dy=26):
    for i, (text, colour) in enumerate(lines):
        yy = y + i * dy
        cv2.putText(img, text, (x, yy), cv2.FONT_HERSHEY_SIMPLEX, 0.62,
                    (0, 0, 0), 4, cv2.LINE_AA)
        cv2.putText(img, text, (x, yy), cv2.FONT_HERSHEY_SIMPLEX, 0.62,
                    colour, 2, cv2.LINE_AA)


GOOD, WARN, BAD = (120, 255, 120), (0, 215, 255), (90, 90, 255)


def cmd_live(a):
    """
    Live view with the geometry solved in real time.

    Adjust the camera while watching the numbers instead of guessing and
    re-running. Detection is run on a downscaled frame every Nth frame to keep
    the display responsive; the overlay is drawn at full resolution.
    """
    import time
    from scoring import ring_radius_mm

    spec = SPECS[a.target]
    cap = target0.open_camera(a.device, 1920, 1080)
    ds = a.detect_scale
    tf, info, ms = None, {}, 0.0
    frame_i = 0
    OUT.mkdir(exist_ok=True)

    print("\n  LIVE - adjust the camera while watching the numbers.")
    print("    ratio   want >= 0.990   (square the camera to the card)")
    print("    RMS     want <= 0.50 px (focus)")
    print("    fill    want 85-95%     (move closer/further)")
    print("    offset  want ~0,0       (recentre the card)")
    print("    q quit    s save snapshot\n")

    while True:
        ok, bgr = cap.read()
        if not ok:
            continue
        gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
        H, W = gray.shape

        if frame_i % a.every == 0:
            t0 = time.time()
            small = (cv2.resize(gray, None, fx=ds, fy=ds,
                                interpolation=cv2.INTER_AREA)
                     if ds != 1.0 else gray)
            tf_new, info = establish(small.astype(np.float32), spec, verbose=False)
            tf = _scale_tf(tf_new, 1.0 / ds) if (tf_new and ds != 1.0) else tf_new
            ms = (time.time() - t0) * 1000.0
        frame_i += 1

        vis = bgr.copy()
        cv2.drawMarker(vis, (W // 2, H // 2), (255, 200, 0),
                       cv2.MARKER_CROSS, 46, 1)

        focus = float(cv2.Laplacian(gray, cv2.CV_64F).var())
        sat = float((gray >= 254).mean() * 100.0)
        lines = [(f"FOCUS {focus:7.1f}    SAT {sat:4.1f}%    "
                  f"solve {ms:5.1f} ms", GOOD if sat < 0.5 else WARN)]

        if tf is None:
            lines.append(("TARGET NOT FOUND - check lighting and framing", BAD))
        else:
            draw_rings(vis, tf, spec)
            r1 = ring_radius_mm(spec, 1) / tf.mm_per_px
            fill = 2 * r1 / H * 100.0
            dx, dy = tf.cx - W / 2.0, tf.cy - H / 2.0
            # RMS comes back in DOWNSCALED pixels; convert to full-frame px
            # or the focus check is silently too lenient.
            ratio = tf.axis_ratio
            rms = info.get("edge_rms_px", float("nan")) / ds

            lines.append((f"ratio {ratio:.4f}"
                          f"{'  OK' if ratio >= 0.99 else '  SQUARE THE CAMERA UP'}",
                          GOOD if ratio >= 0.99 else (WARN if ratio >= 0.97 else BAD)))
            lines.append((f"edge RMS {rms:5.2f} px"
                          f"{'  OK' if rms <= 0.5 else '  ADJUST FOCUS'}",
                          GOOD if rms <= 0.5 else WARN))
            lines.append((f"scale {tf.mm_per_px:.4f} mm/px "
                          f"({1/tf.mm_per_px:4.1f} px/mm)", GOOD))

            hint = ("OK" if 85 <= fill <= 95 else
                    ("MOVE CLOSER" if fill < 85 else "MOVE BACK"))
            lines.append((f"fill {fill:5.1f}% of height   {hint}",
                          GOOD if 85 <= fill <= 95 else WARN))

            move = []
            if abs(dx) > 25:
                move.append("card RIGHT" if dx < 0 else "card LEFT")
            if abs(dy) > 25:
                move.append("card DOWN" if dy < 0 else "card UP")
            lines.append((f"offset dx {dx:+6.0f} dy {dy:+6.0f} px"
                          + ("   move " + " and ".join(move) if move else "   OK"),
                          GOOD if not move else WARN))

            over = [n for n, v in (("left", tf.cx - r1), ("top", tf.cy - r1),
                                   ("right", W - (tf.cx + r1)),
                                   ("bottom", H - (tf.cy + r1))) if v < 0]
            lines.append((f"clipping: {', '.join(over) if over else 'none'}",
                          BAD if over else GOOD))

        _hud(vis, lines)
        disp = cv2.resize(vis, (1280, int(1280 * H / W)))
        cv2.imshow("phase1 live - q to quit", disp)
        k = cv2.waitKey(1) & 0xFF
        if k == ord('q'):
            break
        if k == ord('s'):
            cv2.imwrite(str(OUT / "live_snapshot.png"), bgr)
            cv2.imwrite(str(OUT / "live_overlay.png"), vis)
            print(f"  saved -> {OUT/'live_snapshot.png'} and live_overlay.png")

    cap.release()
    cv2.destroyAllWindows()


def main():
    p = argparse.ArgumentParser(description="Phase 1 - self-locating scorer")
    sub = p.add_subparsers(dest="cmd", required=True)
    for name, fn, h in (("locate", cmd_locate, "show the derived geometry"),
                        ("score", cmd_score, "find and score holes"),
                        ("shot", cmd_shot, "before/after: score the new hole"),
                        ("live", cmd_live, "live view with real-time geometry")):
        s = sub.add_parser(name, help=h)
        s.set_defaults(func=fn)
        s.add_argument("--target", choices=sorted(SPECS), default="pistol")
        s.add_argument("--device", type=int, default=2)
        s.add_argument("--frames", type=int, default=8)
        s.add_argument("--expect", type=int, default=None)
        s.add_argument("--image", default=None,
                       help="score a saved image instead of the camera")
        s.add_argument("--roi", action="store_true",
                       help="crop using calib.json's ROI (default: full frame)")
        s.add_argument("--every", type=int, default=3,
                       help="live: solve geometry every Nth frame")
        s.add_argument("--detect-scale", type=float, default=0.5,
                       help="live: downscale factor for the solve")
    a = p.parse_args()
    a.func(a)


if __name__ == "__main__":
    main()
