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
from geometry import (find_target_frame, refine_bull_ellipse, fit_perspective,
                      flatten_illumination, draw_rings, offscreen_sides)
from scoring import SPECS, PISTOL, score_xy, decimal_step_mm, on_card

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
    tf_e, info = refine_bull_ellipse(flat, tf0)
    tf, pinfo = fit_perspective(flat, tf_e, spec)
    info.update(pinfo)
    if verbose:
        print(f"  aiming mark : ring {spec.black_ring} = {spec.black_dia_mm} mm")
        print(f"  axis ratio  : {tf.axis_ratio:.4f}"
              f"  -> view ~{tf.tilt_deg:.0f} deg off-axis")
        if info.get("refined"):
            print(f"  edge fit    : {info['edge_points']} points, "
                  f"RMS {info['edge_rms_px']:.2f} px")
        else:
            print(f"  edge fit    : NOT applied ({info.get('reason')})")
        if pinfo.get("perspective"):
            print(f"  model       : perspective + lens, from "
                  f"{len(pinfo['rings'])} rings")
            print(f"  ring fit    : {pinfo['points']} points, "
                  f"RMS {pinfo['rms_mm']:.3f} mm "
                  f"({pinfo['rejected']} rejected)")
            print(f"  lens        : k1 {pinfo['k1']:+.3f}  k2 {pinfo['k2']:+.3f}")
            print(f"  perspective : scale varies {pinfo['scale_spread_pct']:.1f}% "
                  f"across the aiming mark")
            print(f"                true centre is {pinfo['centre_shift_px']:.1f} px "
                  f"from the ellipse centre")
            fw, (fr, fa) = pinfo["flat_worst_mm"], pinfo["flat_worst_at"]
            flag = "OK" if abs(fw) <= 0.1 else "NOT FLAT"
            print(f"  card flat   : worst {fw:+.2f} mm (ring {fr}, {fa} deg; "
                  f"0=right 90=up)  {flag}")
            if abs(fw) > 0.1:
                print("  ! Part of the card is not flat. Off-axis, a bump "
                      "shifts what the")
                print("    camera sees; scores near it can be off by about "
                      "that much.")
        else:
            print(f"  model       : ELLIPSE ONLY - {pinfo.get('reason')}")
            if tf.axis_ratio < 0.98:
                print("  ! The camera is off-axis but the perspective fit "
                      "failed, so scores")
                print("    will be wrong away from the centre. Check the ring "
                      "lines are visible.")
        print(f"  centre      : ({tf.cx:.2f}, {tf.cy:.2f}) px")
        print(f"  scale       : {tf.mm_per_px:.5f} mm/px at the centre "
              f"({1/tf.mm_per_px:.1f} px/mm)")
        from scoring import ring_radius_mm as _rr
        over = offscreen_sides(tf, _rr(spec, 1), gray.shape)
        if over:
            print(f"\n  ! The ring-1 scoring edge runs outside the frame on the "
                  f"{', '.join(over)}.")
            print("    Shots landing there cannot be seen. Recentre the card.")
    return tf, info


def report(holes, tf, spec, vis=None, quiet=False, rule="gauge"):
    """
    rule "pellet":  DEFAULT for `shot`. How the shooter actually judges: the
                    pellet's own mark (tears folded back) touching the line.
                    Position = region centroid; the mark is PELLET_MARK_MM
                    across. Matched 20/20 shooter calls (2026-11). If the hole
                    overlaps an earlier one, the centroid is dragged into the
                    old hole, so the circle-fit position is used instead.
    rule "gauge":   official - a 4.5 mm circle at the circle-fit centre must
                    touch the line (the ISSF plug gauge; tears do not count).
    rule "visible": the visible hole, tears included (18/20: a tear reaching
                    a line the pellet did not counted as a touch).
    """
    from scoring import score as _score, PELLET_MARK_MM, ring_radius_mm, \
        LINE_CALL_MM
    rows = []
    for h in holes:
        cx, cy = tf.to_mm(h["xw"], h["yw"])        # region centroid
        if h.get("x_mm") is not None:              # circle-fitted pellet
            fx, fy = h["x_mm"], h["y_mm"]
        else:
            fx, fy = cx, cy
        alt = None
        if rule == "pellet":
            use_fit = h.get("overlap", False)
            x_mm, y_mm = (fx, fy) if use_fit else (cx, cy)
            s = score_xy(x_mm, y_mm, spec, pellet_mm=PELLET_MARK_MM)
            s["rule"] = "pellet"
            # the other position estimate, scored the same way
            alt = score_xy(*((cx, cy) if use_fit else (fx, fy)), spec,
                           pellet_mm=PELLET_MARK_MM)
        else:
            x_mm, y_mm = fx, fy
            s = score_xy(x_mm, y_mm, spec)
            s["rule"] = "gauge"
            alt = score_xy(cx, cy, spec)
            if rule == "visible" and h.get("vis_r_edge") is not None:
                g = s
                s = _score(h["vis_r_edge"], spec, pellet_mm=0.0)
                s.update(x_mm=x_mm, y_mm=y_mm, r_mm=g["r_mm"], rule="visible",
                         gauge_decimal=g["decimal"])
                alt = None
        # The circle fit and the centroid can disagree by 1-2 mm on torn
        # paper, and neither is always right. When the span between them
        # (plus the line-call margin) crosses a ring line, the ring itself is
        # not known: flag it.
        s["ambiguous"] = False
        if alt is not None and h.get("x_mm") is not None:
            s["alt_decimal"] = alt["decimal"]
            lo = min(s["r_edge_mm"], alt["r_edge_mm"]) - LINE_CALL_MM
            hi = max(s["r_edge_mm"], alt["r_edge_mm"]) + LINE_CALL_MM
            s["ambiguous"] = any(lo <= ring_radius_mm(spec, k) <= hi
                                 for k in range(1, 11))
        s["overlap"] = h.get("overlap", False)
        s["check"] = s["line_call"] or s["ambiguous"] or s["overlap"]
        s["clipped"] = h.get("clipped", False)
        s["dia_mm"] = h["diam_px"] * tf.local_mm_per_px(h["xw"], h["yw"])
        s["circ"] = h["circ"]
        rows.append(s)
        if vis is not None:
            mx, my = tf.from_mm(x_mm, y_mm)
            c = (int(round(mx)), int(round(my)))
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
        if s["line_call"]:
            flag += f"  LINE ({s['line_mm']:.2f} mm) - check"
        if s["ambiguous"]:
            flag += f"  RING UNCERTAIN ({s['alt_decimal']} by the other position) - check"
        if s["overlap"]:
            flag += "  OVERLAPS EARLIER HOLE - check"
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
    holes, _, _ = target0.detect_holes(gray, tf.mm_per_px)
    holes, _ = _keep_on_card(holes, tf, spec)
    if a.expect is not None and len(holes) > a.expect:
        holes.sort(key=lambda d: d["peak"] * d["area_px"], reverse=True)
        holes = holes[:a.expect]
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


def _shot_once(a, spec, prior=()):
    """
    Baseline, then a new shot. Scores only what changed. Returns a result
    dict (or None if the target could not be found).

    The two captures are REGISTERED through the target itself before being
    differenced. Without that, any camera movement between them turns every
    printed ring line into a bright edge in the difference image, and you get
    dozens of phantom "shots" spaced exactly one ring apart.
    """
    from geometry import register, frame_shift_mm, new_light

    OUT.mkdir(exist_ok=True)
    n = None
    if a.before:
        # replay: --before is the baseline frame, --image the after frame
        if not a.image:
            sys.exit("  --before needs --image (the after frame)")
        b = cv2.imread(a.before, cv2.IMREAD_GRAYSCALE)
        if b is None:
            sys.exit(f"could not read {a.before}")
        before = b.astype(np.float32)
    else:
        input("\nBASELINE: leave the card as-is and press ENTER...")
        before = acquire(a)
    tf_b, _ = establish(before, spec, verbose=False)
    if tf_b is None:
        print("  could not locate the target in the baseline frame")
        return None

    if not a.before:
        input("Now ADD A SHOT, then press ENTER...")
    after = acquire(a)
    # keep every shot's raw frames, numbered, so any shot can be re-scored:
    #   shot --before out/shots/003_before.png --image out/shots/003_after.png
    if not a.before:
        sd = OUT / "shots"
        sd.mkdir(parents=True, exist_ok=True)
        n = 1 + max([int(p.name[:3]) for p in sd.glob("[0-9][0-9][0-9]_after.png")]
                    or [0])
        for tag, img in (("before", before), ("after", after)):
            cv2.imwrite(str(sd / f"{n:03d}_{tag}.png"),
                        np.clip(img, 0, 255).astype(np.uint8))
        print(f"  saved as shot {n:03d} -> {sd}/{n:03d}_before.png / _after.png")
    return _score_pair(a, spec, before, tf_b, after, n, prior=prior)


def _next_shot_number():
    sd = OUT / "shots"
    sd.mkdir(parents=True, exist_ok=True)
    return 1 + max([int(p.name[:3]) for p in sd.glob("[0-9][0-9][0-9]_after.png")]
                   or [0])


def _score_pair(a, spec, before, tf_b, after, n, tf=None, verbose=True,
                prior=()):
    """
    Score what changed between a baseline and an after frame. Returns a result
    dict, or None if the target could not be found in the after frame.
    """
    from geometry import register, frame_shift_mm, new_light

    if verbose:
        print(f"\n{spec.name}")
    geo = {}
    if tf is None:
        tf, geo = establish(after, spec, verbose=verbose)
    if tf is None:
        return None

    # --- register the baseline into the new frame's geometry ------------
    moved_mm, scale_pct = frame_shift_mm(tf_b, tf)
    # Dense remap after-px -> target mm -> before-px. Exact under perspective
    # and lens distortion, which a single 3x3 warp is not.
    before_reg = register(before, tf_b, tf, after.shape)

    print(f"\n  camera moved {moved_mm:.2f} mm between captures "
          f"(scale change {scale_pct:+.2f}%)")
    if moved_mm > 1.0:
        print("  -> registered through the target, so this is corrected.")
    if moved_mm > 25.0:
        print("  ! That is a large move. If the card itself was disturbed, the")
        print("    difference is meaningless - redo the baseline.")

    # Brighter than every baseline pixel nearby - absorbs printed edges that
    # shifted or changed sharpness between frames; see geometry.new_light.
    diff = new_light(after, before_reg)

    # Filters matter here. A new region must be hole-SIZED; a crescent from an
    # overlapping shot is not round, so circularity is kept permissive but not
    # disabled, or registration residue floods the list.
    hd, _, _ = target0.detect_holes(diff, tf.mm_per_px, min_mm=2.0,
                                    min_circularity=0.30)
    hd, off = _keep_on_card(hd, tf, spec)
    if off:
        print(f"\n  ignored {off} change(s) off the card (background glints, "
              "movement)")
    if a.expect is not None:
        hd.sort(key=lambda d: d["peak"] * d["area_px"], reverse=True)
        hd = hd[:a.expect]
    hd.sort(key=lambda h: h["area_px"], reverse=True)

    OUT.mkdir(exist_ok=True)
    cv2.imwrite(str(OUT / "p1_shot_diff.png"),
                np.clip(diff * 3, 0, 255).astype(np.uint8))

    if not hd:
        print("\n  No new region found. Was a shot actually added?")
        return {"n": n, "found": False}

    # Pellet centre from a circle of the pellet's known size fitted to the
    # round part of the edge. The centroid is dragged along paper tears and
    # is wrong for an overlap crescent; this is not.
    for h in hd:
        f = target0.fit_pellet(diff, h, tf.to_mm)
        h["fit"] = f
        if f["ok"]:
            h["x_mm"], h["y_mm"] = f["x_mm"], f["y_mm"]

    print("\n  NEW region(s), largest first:")
    vis = cv2.cvtColor(np.clip(after, 0, 255).astype(np.uint8), cv2.COLOR_GRAY2BGR)
    draw_rings(vis, tf, spec)
    # visible-hole edge, from the PLAIN difference (see target0.visible_edge)
    plain = np.clip(after.astype(np.float32) - before_reg, 0, None)
    # `prior` = centres (target mm) of earlier holes on this card. If the new
    # visible region runs into one, the shot tore into an old hole: the
    # visible edge then belongs partly to the OLD hole (a real 7 read as 9),
    # so fall back to the pellet-sized gauge and flag it.
    from scoring import PELLET_MM as _P
    for h in hd:
        ve = target0.visible_edge(plain, h, tf.to_mm)
        h["vis_r_edge"] = ve["r_edge"] if ve else None
        h["overlap"] = False
        if ve is not None and len(prior):
            pp = np.asarray(prior, float)
            dmin = float(np.min(np.hypot(
                ve["pts_mm"][:, None, 0] - pp[None, :, 0],
                ve["pts_mm"][:, None, 1] - pp[None, :, 1])))
            if dmin < _P / 2.0 + 0.5:
                h["overlap"] = True
                h["vis_r_edge"] = None
    rows = report(hd, tf, spec, vis, rule=getattr(a, "rule", "gauge"))

    from scoring import PELLET_MM
    for i, h in enumerate(hd):
        f = h["fit"]
        cx, cy = tf.to_mm(h["xw"], h["yw"])
        nominal = np.pi * (PELLET_MM / 2.0 / tf.local_mm_per_px(h["xw"], h["yw"])) ** 2
        frac = h["area_px"] / nominal
        shape = ("sliver" if frac < 0.15 else "partial / overlapping"
                 if frac < 0.75 else "about one pellet" if frac < 2.5
                 else "larger than a pellet - torn or merged")
        if f["ok"]:
            moved = float(np.hypot(f["x_mm"] - cx, f["y_mm"] - cy))
            print(f"    [{i}] {shape}; pellet circle fitted to {f['arc_deg']:.0f} "
                  f"deg of round edge, {moved:.2f} mm from the region centroid")
        else:
            print(f"    [{i}] {shape}; NO round pellet edge found - scored from "
                  "the region centroid, treat with caution")

    best = rows[0]
    print(f"\n  SHOT: {best['decimal']} decimal / ring {best['integer']}"
          f"   at x {best['x_mm']:+.2f} mm  y {best['y_mm']:+.2f} mm"
          + ("   INNER TEN" if best["inner_ten"] else "")
          + (f"   LINE CALL - edge {best['line_mm']:.2f} mm from a ring line, "
             "check by eye" if best["line_call"] else "")
          + (f"   RING UNCERTAIN - {best['alt_decimal']} by the other method, "
             "check by eye" if best["ambiguous"] else "")
          + ("   OVERLAPS EARLIER HOLE - scored by gauge, check by eye"
             if best["overlap"] else ""))
    if len(hd) > 1:
        print(f"  ({len(hd)-1} smaller region(s) also found - if those are not")
        print("   real shots, pass --expect 1)")
    cv2.imwrite(str(OUT / "p1_shot.png"), vis)
    if n is not None:
        cv2.imwrite(str(OUT / "shots" / f"{n:03d}_overlay.png"), vis)
    print(f"\n  overlay -> {OUT/'p1_shot.png'}")
    print(f"  difference image -> {OUT/'p1_shot_diff.png'}\n")
    f = hd[0]["fit"]
    return {"n": n, "found": True, "row": best, "fit_ok": f["ok"],
            "arc_deg": f["arc_deg"], "regions": len(hd), "tf": tf,
            "geo_rms": geo.get("rms_mm"), "geo_persp": geo.get("perspective")}


def cmd_shot(a):
    """
    Score new shots one at a time. With --count N, runs N shots in a row and
    after each asks for your by-eye call, logged next to the system's score in
    out/shots/calls.csv so the two can be compared shot by shot.

    The two captures are REGISTERED through the target itself before being
    differenced; see _shot_once.
    """
    import csv
    from datetime import datetime

    spec = SPECS[a.target]
    if a.before:                                 # replay a saved shot
        _shot_once(a, spec)
        return

    if a.auto:
        _shot_auto(a, spec)
        return

    prior = []          # hole centres on this card, this series
    for i in range(a.count):
        if a.count > 1:
            print(f"\n========== shot {i + 1} of {a.count} ==========")
        res = _shot_once(a, spec, prior)
        if res is None or not res.get("found"):
            if a.count > 1 and input("  Nothing scored. Continue the series? "
                                     "[Y/n] ").strip().lower() == "n":
                break
            continue
        r = res["row"]
        call = ""
        if a.count > 1 or a.ask:
            call = input("  Your by-eye call (ring, and which end is the impact "
                         "if torn) - ENTER to skip:\n  > ").strip()
        _log_shot(res, call)
        prior.append((r["x_mm"], r["y_mm"]))
    _print_log(max(a.count, 5))


SHOT_LOG_FIELDS = ["when", "shot", "decimal", "ring", "x_mm", "y_mm", "r_mm",
                   "fit", "arc_deg", "regions", "your_call"]


def _log_shot(res, call=""):
    """Append one scored shot to out/shots/calls.csv."""
    import csv
    from datetime import datetime
    log = OUT / "shots" / "calls.csv"
    r = res["row"]
    new = not log.exists()
    log.parent.mkdir(parents=True, exist_ok=True)
    with open(log, "a", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=SHOT_LOG_FIELDS)
        if new:
            w.writeheader()
        w.writerow({"when": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                    "shot": f"{res['n']:03d}", "decimal": r["decimal"],
                    "ring": r["integer"], "x_mm": round(r["x_mm"], 2),
                    "y_mm": round(r["y_mm"], 2), "r_mm": round(r["r_mm"], 2),
                    "fit": "circle" if res["fit_ok"] else "centroid",
                    "arc_deg": round(res["arc_deg"]),
                    "regions": res["regions"], "your_call": call})


def _print_log(last):
    import csv
    log = OUT / "shots" / "calls.csv"
    if not log.exists():
        return
    with open(log) as fh:
        rows = list(csv.DictReader(fh))
    print(f"\n  shot log ({log}):")
    print(f"  {'shot':>4} {'score':>6} {'ring':>4} {'fit':>8}  your call")
    for row in rows[-last:]:
        print(f"  {row['shot']:>4} {row['decimal']:>6} {row['ring']:>4} "
              f"{row['fit']:>8}  {row['your_call']}")
    print()


class _LiveCamera:
    """
    Keep the camera open and read continuously in a background thread, so a
    capture returns FRESH frames immediately instead of reopening the device
    (seconds) or getting stale buffered frames.
    """

    def __init__(self, device, w=1920, h=1080):
        import threading
        self.cap = target0.open_camera(device, w, h)
        self.lock = threading.Lock()
        self.frame, self.seq = None, 0
        self.running = True
        self.th = threading.Thread(target=self._run, daemon=True)
        self.th.start()

    def _run(self):
        while self.running:
            ok, bgr = self.cap.read()
            if ok:
                with self.lock:
                    self.frame, self.seq = bgr, self.seq + 1

    def grab(self, n=8, timeout=5.0):
        """Average the next n frames that arrive AFTER this call."""
        import time
        with self.lock:
            start = self.seq
        acc, last, t0 = [], start, time.time()
        while len(acc) < n and time.time() - t0 < timeout:
            with self.lock:
                f, sq = self.frame, self.seq
            if sq > last and f is not None:
                acc.append(cv2.cvtColor(f, cv2.COLOR_BGR2GRAY).astype(np.float32))
                last = sq
            else:
                time.sleep(0.005)
        if not acc:
            raise RuntimeError("camera delivered no frames")
        return np.mean(acc, axis=0)

    def close(self):
        # Release only once the reader has left cap.read(): releasing under a
        # blocked read can hang AVFoundation. The thread is a daemon, so if it
        # is stuck the process still exits.
        self.running = False
        self.th.join(timeout=2.0)
        if not self.th.is_alive():
            self.cap.release()


SOUNDS = {"ready": "/System/Library/Sounds/Hero.aiff",
          "info": "/System/Library/Sounds/Tink.aiff",
          "ok": "/System/Library/Sounds/Glass.aiff",
          "check": "/System/Library/Sounds/Sosumi.aiff",
          "fail": "/System/Library/Sounds/Basso.aiff"}


def _announce(kind, text, enabled=True):
    """
    Tell the shooter at the firing line what happened, without looking: a
    distinct sound per outcome (ok / check / fail), then the result spoken
    with macOS `say`. Non-blocking. Returns (start_time, process) so the
    caller can ignore its OWN announcement on the trigger microphone for as
    long as it actually plays: the laptop speaker near the mic measured
    +52.6 dB for the fail tone - over the shot threshold - so an estimated
    mute window let it retrigger itself.
    """
    import shlex
    import subprocess
    import time
    if not enabled:
        return None
    cmd = f"afplay {shlex.quote(SOUNDS[kind])}"
    if text:
        cmd += f"; say {shlex.quote(text)}"
    try:
        proc = subprocess.Popen(["sh", "-c", cmd], stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL)
    except OSError:
        return None
    return {"start": time.time(), "proc": proc, "end": None}


def _track_announcements(announcements):
    """Record WHEN each announcement finished. Must be called often (every
    loop pass): stamping the end lazily, at the next sound, marked that sound
    - usually the next SHOT - as part of the announcement (2026-11: 7 real
    shots were "ignored: own announcement")."""
    import time
    now = time.time()
    for an in announcements:
        if an["end"] is None and an["proc"].poll() is not None:
            an["end"] = now


def _muted(announcements, when, tail=0.7):
    """True if wall-clock time `when` falls while (or just after) one of our
    own announcements was playing."""
    import time
    now = time.time()
    for an in announcements:
        if an["end"] is None and an["proc"].poll() is not None:
            # finished but never stamped: we do not know when, so do NOT
            # assume it was still playing
            an["end"] = an["start"]
        end = an["end"] if an["end"] is not None else now + 1e9
        if an["start"] - 0.1 <= when <= end + tail:
            return True
    return False


def _direction(x_mm, y_mm, inner_ten=False):
    """Where the shot is from the centre, in the shooter's words: high, high
    right, right, low right, low, low left, left, high left - or centre for an
    inner ten. Target +y is up (image-up through the centre, see
    geometry.fit_perspective)."""
    import math
    if inner_ten or math.hypot(x_mm, y_mm) < 1.0:
        return "centre"
    names = ["right", "high right", "high", "high left",
             "left", "low left", "low", "low right"]
    ang = math.degrees(math.atan2(y_mm, x_mm)) % 360.0
    return names[int(((ang + 22.5) % 360.0) // 45.0)]


def _spoken(r, res):
    """The result as a short phrase for `say`."""
    words = (f"{r['decimal']:.1f}, "
             + _direction(r["x_mm"], r["y_mm"], r["inner_ten"])
             + (", inner ten" if r["inner_ten"] else ""))
    why = []
    if r.get("line_call"):
        why.append("line call")
    if r.get("ambiguous"):
        why.append("ring uncertain")
    if r.get("overlap"):
        why.append("overlaps a hole")
    if not res["fit_ok"] and r.get("rule") == "gauge":
        why.append("rough hole")
    return words, why


def _same_card(old_img, old_tf, new_img, new_tf, holes_mm, r_mm=1.5):
    """
    After the target vanished and came back: is it the same card (someone
    just blocked the view) or a new one? Look at where the earlier holes
    were. Lit through the diffuser they are bright; on a fresh card those
    spots are plain paper or black. Same card if most holes are still there.
    """
    if not holes_mm:
        return True
    still = 0
    for x, y in holes_mm:
        vals = []
        for img, tf in ((old_img, old_tf), (new_img, new_tf)):
            px, py = tf.from_mm(x, y)
            rr = max(2, int(r_mm / tf.local_mm_per_px(px, py)))
            px, py = int(round(px)), int(round(py))
            patch = img[max(0, py - rr):py + rr + 1, max(0, px - rr):px + rr + 1]
            vals.append(float(np.mean(patch)) if patch.size else 0.0)
        if vals[1] > vals[0] - 40.0:       # still about as bright: still there
            still += 1
    return still >= 0.5 * len(holes_mm)


def _scene_moving(f0, t0, f1, t1, spec, thresh=30.0, frac=0.01):
    """
    Did a large part of the card change between two frames? A person, a hand
    or a swinging card changes a big area; a new pellet hole is ~0.05% of it.

    Measured only INSIDE RING 1, where the geometry is fitted. The card's own
    outer edge lies beyond the outermost ring, so its registration is an
    extrapolation that shifts 2-3 px between frames minutes apart (lens terms
    vary slightly per frame): on 2026-11 data the card outline alone made a
    still scene read 2.1% changed, which would reject a real shot as
    "movement". Real shot pairs read 0.10-0.46%.
    """
    from geometry import register, new_light
    from scoring import ring_radius_mm
    H, W = f1.shape[:2]
    th = np.linspace(0, 2 * np.pi, 180, endpoint=False)
    r1 = ring_radius_mm(spec, 1)
    xs, ys = t1.from_mm(r1 * np.cos(th), r1 * np.sin(th))
    x0, x1 = int(max(0, np.min(xs))), int(min(W, np.max(xs)))
    y0, y1 = int(max(0, np.min(ys))), int(min(H, np.max(ys)))
    if x1 <= x0 or y1 <= y0:
        return True
    mask = np.zeros((y1 - y0, x1 - x0), np.uint8)
    poly = np.stack([xs - x0, ys - y0], 1).astype(np.int32)
    cv2.fillPoly(mask, [poly], 1)
    reg = register(f0, t0, t1, f1.shape)
    # Changes beyond everything nearby, both ways (new_light both directions):
    # a plain |difference| counted every printed line that shifted with focus
    # or scale as "movement" - and then a real hole triggered a re-baseline
    # that swallowed it.
    a, b = f1[y0:y1, x0:x1], reg[y0:y1, x0:x1]
    d = np.maximum(new_light(a, b), new_light(b, a))
    inside = mask > 0
    return float((d[inside] > thresh).mean()) > frac


def _shot_auto(a, spec):
    """
    Hands-free scoring. Two ways a shot is noticed, one way it is scored:

      SOUND   the camera's microphone hears the impact (measured 2026-11:
              shots +59 to +65 dB over the room floor, 280-370 ms of ringing;
              loudest non-shot +43 dB). Fast: scored ~1 s after impact.
      CAMERA  every --watch seconds the camera compares the card with the
              baseline. A hole-sized new region that is still there on the
              next check is scored as a shot "found without a sound". This is
              the safety net: one real shot (2026-11) made no trigger and was
              lumped into the next shot's comparison and dropped.

    The same camera check watches for MOVEMENT: if a large part of the card
    changed (a person mounting a card, a hand, a swinging card) nothing is
    scored and no baseline is taken until the view is still. A baseline taken
    with the shooter in frame (2026-11) turned a magnet's clang into a
    phantom shot.

    A trigger with no new hole is harmless: not scored, baseline kept, so a
    hole can never be absorbed into the baseline without being scored.
    """
    import contextlib
    import io
    import queue
    import time
    import sounddevice as sd
    import audio
    from geometry import register, new_light
    from scoring import PELLET_MM

    if a.expect is None:      # one new hole per before/after comparison
        a.expect = 1
    idx, info = audio.find_input(a.mic)
    rate = int(info["default_samplerate"])
    q = queue.Queue()

    def cb(indata, frames, t, status):
        q.put(indata.mean(axis=1).astype(np.float32).copy())

    def silent():
        return (contextlib.nullcontext() if a.verbose
                else contextlib.redirect_stdout(io.StringIO()))

    def locate(img):
        with contextlib.redirect_stdout(io.StringIO()):
            return establish(img, spec, verbose=False)[0]

    print(f"\n  AUTO: listening on '{info['name']}', camera {a.device}. "
          "Ctrl+C to finish.")
    print(f"  sound trigger: > +{a.trigger_db:.0f} dB over the room, "
          f">= {a.trigger_ms:.0f} ms; capture {a.settle:.1f} s after impact.")
    print(f"  camera check every {a.watch:.0f} s: catches shots without a "
          "sound, card changes, people in view.")
    cam = _LiveCamera(a.device)
    st = {"prior": [], "scored": 0, "card_no": 1, "ann": [],
          "last_fail_say": -1e9, "dirty": False}

    def say(kind, text):
        an = _announce(kind, text, a.speak)
        if an:
            st["ann"].append(an)
            st["ann"][:] = st["ann"][-5:]

    def score_now(label):
        """Capture the after frame, score it against the baseline, report.
        Returns True if a shot was scored (and the baseline moved on)."""
        after = cam.grab(a.frames)
        n = _next_shot_number()
        print(f"  ===== shot {n:03d}  ({label})")
        # A real shot changes a hole-sized patch. If large parts of the card
        # changed, something moved (the 2026-11 phantom: a magnet's clang
        # while the shooter, in the baseline frame, was mounting the card).
        tf_a = locate(after)
        if tf_a is not None and _scene_moving(st["before"], st["tf_b"], after,
                                              tf_a, spec):
            stamp = time.strftime("%H%M%S")  # never silent, never lose frames
            for tag, img in (("before", st["before"]), ("after", after)):
                cv2.imwrite(str(OUT / "shots" / f"unscored_{stamp}_{tag}.png"),
                            np.clip(img, 0, 255).astype(np.uint8))
            print("  view changed too much (person / card moving) - NOT scored;"
                  " new baseline once the view is still. Frames: "
                  f"{OUT / 'shots'}/unscored_{stamp}_*.png\n", flush=True)
            st["dirty"] = True
            if time.time() - st["last_fail_say"] > 10.0:
                say("fail", "not scored, view moving")
                st["last_fail_say"] = time.time()
            return False
        with silent():
            res = _score_pair(a, spec, st["before"], st["tf_b"], after, n,
                              verbose=a.verbose, prior=st["prior"])
        if res is None:
            time.sleep(0.5)                  # something in the way - retry
            after = cam.grab(a.frames)
            with silent():
                res = _score_pair(a, spec, st["before"], st["tf_b"], after, n,
                                  verbose=a.verbose, prior=st["prior"])
        sdir = OUT / "shots"
        if res is None or not res.get("found"):
            stamp = time.strftime("%H%M%S")  # never lose frames
            for tag, img in (("before", st["before"]), ("after", after)):
                cv2.imwrite(str(sdir / f"unscored_{stamp}_{tag}.png"),
                            np.clip(img, 0, 255).astype(np.uint8))
            why = ("could NOT LOCATE THE TARGET in the after frame"
                   if res is None else "no new hole on the card")
            print(f"  {why} - not scored, baseline kept. Frames: "
                  f"{sdir}/unscored_{stamp}_*.png\n", flush=True)
            if time.time() - st["last_fail_say"] > 10.0:   # loop backstop
                say("fail", "shot not scored")
                st["last_fail_say"] = time.time()
            return False
        for tag, img in (("before", st["before"]), ("after", after)):
            cv2.imwrite(str(sdir / f"{n:03d}_{tag}.png"),
                        np.clip(img, 0, 255).astype(np.uint8))
        r = res["row"]
        print(f"  >>> card shot {len(st['prior']) + 1}:  "
              f"{r['decimal']}   ring {r['integer']}   "
              f"{_direction(r['x_mm'], r['y_mm'], r['inner_ten']):<10} "
              f"x {r['x_mm']:+.1f}  y {r['y_mm']:+.1f} mm"
              + ("   INNER TEN" if r["inner_ten"] else "")
              + ("" if res["fit_ok"] or r.get("rule") != "gauge"
                 else "   (rough hole - check)")
              + (f"   LINE CALL ({r['line_mm']:.2f} mm) - check by eye"
                 if r["line_call"] else "")
              + (f"   RING UNCERTAIN (or {r['alt_decimal']}) - check by eye"
                 if r["ambiguous"] else "")
              + ("   OVERLAPS EARLIER HOLE - check by eye" if r["overlap"] else "")
              + "\n", flush=True)
        # Each hole in the black tears up ring lines the geometry is fitted
        # to; say so if the fit is degrading as the card fills up.
        if res.get("geo_persp") is False:
            print("  ! geometry: perspective fit FAILED on this frame - "
                  "scores are unreliable; consider a fresh card\n", flush=True)
            say("check", "geometry warning, consider a fresh card")
        elif res.get("geo_rms") is not None and res["geo_rms"] > 0.25:
            print(f"  ! geometry: ring fit {res['geo_rms']:.2f} mm (usually "
                  "~0.1-0.15) - the card is getting torn up\n", flush=True)
        words, flags = _spoken(r, res)
        if label.startswith("camera"):
            flags = ["found without a sound"] + flags
        _log_shot(res)
        st["prior"].append((r["x_mm"], r["y_mm"]))
        k = len(st["prior"])                 # shot number ON THIS CARD
        full = a.per_card and k == a.per_card
        tail = f". {a.per_card} shots, change the card" if full else ""
        # Lead with the shot number on this card, so a missed shot is noticed
        # at once ("shot five" when you expected six).
        if flags:
            say("check", f"shot {k}. check. " + ", ".join(flags) + f". {words}"
                + tail)
        else:
            say("ok", f"shot {k}. {words}" + tail)
        if full:
            print(f"  -- {a.per_card} shots on card {st['card_no']}: change the "
                  "card (it will say 'card off', then 'new card, ready') --\n",
                  flush=True)
        st["scored"] += 1
        st["before"], st["tf_b"] = after, res["tf"]
        return True

    try:
        time.sleep(1.0)                          # let exposure settle
        st["before"] = cam.grab(a.frames)
        st["tf_b"] = locate(st["before"])
        if st["tf_b"] is None:
            print("  could not locate the target - check framing and lighting")
            return
        print("  baseline taken. Ready - fire when you like.\n")
        say("ready", "ready")

        det = audio.EventDetector(rate, ratio_db=min(20.0, a.trigger_db))
        with sd.InputStream(device=idx, channels=min(2, info["max_input_channels"]),
                            samplerate=rate, blocksize=int(rate * 0.02),
                            callback=cb):
            t_audio0 = time.time()
            last_trig = -1e9
            w = {"card_on": True, "misses": 0, "still": 0, "cand": None,
                 "last": None, "next": time.time() + a.watch}

            def new_hole(frame, tf_now):
                """Position (mm) of the strongest hole-sized new region against
                the baseline, or None."""
                d = new_light(frame, register(st["before"], st["tf_b"], tf_now,
                                              frame.shape))
                hd, _, _ = target0.detect_holes(d, tf_now.mm_per_px, min_mm=2.0,
                                                min_circularity=0.30)
                hd, _ = _keep_on_card(hd, tf_now, spec)
                nominal = np.pi * (PELLET_MM / 2.0 / tf_now.mm_per_px) ** 2
                hd = [h for h in hd if h["peak"] >= 40 and
                      h["area_px"] >= 0.5 * nominal]
                if not hd:
                    return None
                h = max(hd, key=lambda h: h["peak"] * h["area_px"])
                return tf_now.to_mm(h["xw"], h["yw"])

            def watch():
                """Card present? View still? New hole without a sound?"""
                nonlocal last_trig
                frame = cam.grab(2)
                tf_now = locate(frame)
                if tf_now is None:
                    w["still"], w["cand"], w["last"] = 0, None, None
                    w["misses"] += 1
                    if w["card_on"] and w["misses"] >= 2:
                        w["card_on"] = False
                        print("  -- target out of view (card off?) --", flush=True)
                        say("info", "card off")
                    return
                w["misses"] = 0
                moving = (w["last"] is not None and
                          _scene_moving(w["last"][0], w["last"][1], frame,
                                        tf_now, spec))
                w["last"] = (frame, tf_now)
                if moving:
                    w["still"], w["cand"] = 0, None
                    st["dirty"] = True
                    if a.verbose:
                        print("    (movement in view - waiting)", flush=True)
                    return
                if w["card_on"] and st["dirty"]:
                    # something moved in view: once still for two checks,
                    # take a fresh baseline so a person caught in the old one
                    # cannot turn into a phantom shot later
                    w["still"] += 1
                    if w["still"] < 2:
                        return
                    w["still"], st["dirty"] = 0, False
                    # never let a re-baseline swallow a shot: if a hole-sized
                    # new region is there against the OLD baseline, score it
                    if new_hole(frame, tf_now) is not None:
                        last_trig = time.time() - t_audio0
                        if score_now("camera - no sound heard"):
                            return
                        # could not score it: keep the OLD baseline (2026-11:
                        # re-baselining here swallowed a real shot). Give up
                        # after 3 tries so a person caught in the baseline
                        # cannot block scoring forever - the frames are saved.
                        st["rebase_tries"] = st.get("rebase_tries", 0) + 1
                        if st["rebase_tries"] < 3:
                            st["dirty"] = True
                            return
                        print("  ! re-baselining over an unscored change - "
                              "check the saved unscored_* frames", flush=True)
                    st["rebase_tries"] = 0
                    new = cam.grab(a.frames)
                    tf_new = locate(new)
                    if tf_new is not None:
                        if st["prior"] and not _same_card(
                                st["before"], st["tf_b"], new, tf_new,
                                st["prior"]):
                            st["prior"].clear()
                            st["card_no"] += 1
                            print(f"  -- new card (card {st['card_no']}) --",
                                  flush=True)
                            say("info", "new card, ready")
                        st["before"], st["tf_b"] = new, tf_new
                        print("  -- view still again, new baseline. Ready --\n",
                              flush=True)
                        say("ready", "ready")
                    return
                if not w["card_on"]:
                    # card back: wait for TWO still checks, then a baseline
                    w["still"] += 1
                    if w["still"] < 2:
                        return
                    w["card_on"], w["still"], st["dirty"] = True, 0, False
                    new = cam.grab(a.frames)
                    tf_new = locate(new)
                    if tf_new is None:
                        w["card_on"] = False
                        return
                    same = _same_card(st["before"], st["tf_b"], new, tf_new,
                                      st["prior"])
                    st["before"], st["tf_b"] = new, tf_new
                    if not st["prior"]:
                        msg = "card back, ready"
                    elif same:
                        msg = "same card, ready"
                    else:
                        st["prior"].clear()
                        st["card_no"] += 1
                        msg = "new card, ready"
                    print(f"  -- {msg} (card {st['card_no']}, new baseline) --\n",
                          flush=True)
                    say("ready", msg)
                    return
                # safety net: a hole-sized new region, stable over two checks
                pos = new_hole(frame, tf_now)
                if pos is None:
                    w["cand"] = None
                    return
                if w["cand"] is not None and np.hypot(pos[0] - w["cand"][0],
                                                      pos[1] - w["cand"][1]) < 3:
                    w["cand"] = None
                    last_trig = time.time() - t_audio0   # mute its late sound
                    score_now("camera - no sound heard")
                else:
                    w["cand"] = pos

            while True:
                try:
                    blk = q.get(timeout=0.2)
                except queue.Empty:
                    blk = None
                _track_announcements(st["ann"])
                if time.time() >= w["next"] and q.qsize() < 5:
                    w["next"] = time.time() + a.watch
                    watch()
                if blk is None:
                    continue
                for e in det.feed(blk):
                    # Muting our own announcements only matters if they come
                    # out of a speaker near the camera (--speaker). With
                    # earbuds it only risked muting real shots.
                    why = ("own announcement"
                           if a.speaker and _muted(st["ann"], t_audio0 + e["t"])
                           else
                           "too quiet" if e["over_db"] < a.trigger_db else
                           "too short" if e["len_ms"] < a.trigger_ms else
                           "echo of last shot" if e["t"] - last_trig < 2.0
                           else None)
                    if a.verbose or (e["over_db"] >= a.trigger_db - 12 and why):
                        # near-misses are always shown: a quiet real shot is
                        # exactly what we need to see if one is ever missed
                        print(f"    sound +{e['over_db']:.1f} dB "
                              f"{max(0.0, e['len_ms']):.0f} ms at {e['t']:.2f} s"
                              + (f"  - ignored: {why}" if why else ""),
                              flush=True)
                    if why:
                        continue
                    last_trig = e["t"]
                    wait = a.settle - (time.time() - (t_audio0 + e["t"]))
                    if wait > 0:
                        time.sleep(wait)
                    if score_now(f"sound +{e['over_db']:.0f} dB"):
                        w["cand"] = None
    except KeyboardInterrupt:
        # The last shot of a session has nothing after it: if its sound was
        # missed and you stop within the camera check's ~4 s, it would be
        # lost (2026-11). Look once more before exiting.
        try:
            print("\n  final check for an unscored hole (Ctrl+C again to "
                  "skip)...", flush=True)
            frames = []
            for _ in range(6):               # wait up to ~6 s for a still view
                f = cam.grab(4)
                t = locate(f)
                if t is None:
                    break
                frames.append((f, t))
                if len(frames) >= 2 and not _scene_moving(
                        frames[-2][0], frames[-2][1], f, t, spec):
                    break
                time.sleep(1.0)
            if frames and "tf_b" in st and st.get("tf_b") is not None:
                f, t = frames[-1]
                from geometry import register as _reg, new_light as _nl
                d = _nl(f, _reg(st["before"], st["tf_b"], t, f.shape))
                hd, _, _ = target0.detect_holes(d, t.mm_per_px, min_mm=2.0,
                                                min_circularity=0.30)
                hd, _ = _keep_on_card(hd, t, spec)
                nominal = np.pi * (PELLET_MM / 2.0 / t.mm_per_px) ** 2
                if any(h["peak"] >= 40 and h["area_px"] >= 0.5 * nominal
                       for h in hd):
                    score_now("camera - found at the end of the session")
                else:
                    print("  nothing unscored.", flush=True)
        except KeyboardInterrupt:
            pass
    finally:
        cam.close()
    print(f"\n  session: {st['scored']} shot(s) scored over "
          f"{st['card_no']} card(s)")
    _print_log(max(st["scored"], 1))


def cmd_bench(a):
    """
    Measure the rig as it stands, for A/B comparisons (camera light on vs off,
    room lights, a new position). Nothing on the card may change during a run.

    Each run appends one labelled row to out/bench.csv and prints every row so
    far, so conditions can be compared side by side. Needs no calib.json.

      geom noise  how far the REPORTED target mm of a fixed point wanders
                  frame to frame, from re-solving the geometry each time.
                  This is score noise that has nothing to do with holes.
      phantoms    regions `shot` would report between two frames where
                  nothing changed. Anything above 0 is a false shot.
      ring RMS    perspective fit quality; edge RMS is focus.
      pix noise   sensor noise, grey levels; sat% = clipped pixels on card.
    """
    import csv
    import time
    from datetime import datetime
    from geometry import register, new_light
    from scoring import ring_radius_mm

    if a.image:
        sys.exit("bench measures the live camera; --image does not apply")
    spec = SPECS[a.target]
    cap = target0.open_camera(a.device, 1920, 1080)
    for _ in range(10):                         # let auto-exposure settle
        cap.read()
    print(f"\n  bench '{a.label}': {a.rounds} rounds of {a.frames} frame(s). "
          "Do not touch anything.")
    frames, tfs, infos = [], [], []
    for i in range(a.rounds):
        g, _ = target0.grab_gray(cap, a.frames)
        tf, info = establish(g, spec, verbose=False)
        if tf is None:
            cap.release()
            sys.exit(f"  round {i+1}: target not found ({info.get('reason')})")
        frames.append(g); tfs.append(tf); infos.append(info)
        print(f"    round {i+1}/{a.rounds}", end="\r")
        time.sleep(0.15)
    cap.release()
    print()

    ref = tfs[0]
    H, W = frames[0].shape[:2]
    # card region = inside ring 1, for image statistics
    th = np.linspace(0, 2 * np.pi, 360, endpoint=False)
    r1 = ring_radius_mm(spec, 1)
    bx, by = ref.from_mm(r1 * np.cos(th), r1 * np.sin(th))
    card = np.zeros((H, W), np.uint8)
    cv2.fillPoly(card, [np.stack([bx, by], 1).astype(np.int32)], 1)
    card = card.astype(bool)
    stack = np.stack(frames)
    pix_noise = float(np.median(stack.std(axis=0, ddof=1)[card]))
    sat = float((stack[0][card] >= 254).mean() * 100)
    Rb = spec.black_dia_mm / 2.0
    inside = np.hypot(*ref.to_mm(*np.meshgrid(np.arange(W), np.arange(H)))) < 0.8 * Rb
    black = float(np.median(stack[0][inside & card]))
    paper = float(np.percentile(stack[0][card & ~inside], 75))

    # score noise from geometry: fixed image points, re-measured each frame
    pts = [(0, 0)] + [(r * np.cos(t), r * np.sin(t))
                      for r in (10, 30, 60) for t in np.radians((0, 90, 180, 270))]
    sds = []
    for x, y in pts:
        px, py = ref.from_mm(x, y)
        m = np.array([t.to_mm(px, py) for t in tfs])
        sds.append(float(np.hypot(*m.std(axis=0, ddof=1))))
    geom_mean, geom_worst = float(np.mean(sds)), float(np.max(sds))
    cen_sd = sds[0]

    phantoms, ph_list, off_card = [], [], 0
    for i, ((g0, t0), (g1, t1)) in enumerate(zip(zip(frames, tfs),
                                                 zip(frames[1:], tfs[1:]))):
        diff = new_light(g1, register(g0, t0, t1, g1.shape))
        hd, _, _ = target0.detect_holes(diff, t1.mm_per_px, min_mm=2.0,
                                        min_circularity=0.30)
        hd, off = _keep_on_card(hd, t1, spec)
        off_card += off
        phantoms.append(len(hd))
        for h in hd:
            x, y = t1.to_mm(h["xw"], h["yw"])
            ph_list.append((i + 1, x, y, h["diam_px"], h["peak"]))
        if hd:
            # Where false shots sit says why: scattered blobs = light/exposure
            # flicker; along printed lines = movement / registration.
            vis = cv2.cvtColor(np.clip(diff * 4, 0, 255).astype(np.uint8),
                               cv2.COLOR_GRAY2BGR)
            for h in hd:
                cv2.circle(vis, (int(h["xw"]), int(h["yw"])), 30, (0, 0, 255), 2)
            OUT.mkdir(exist_ok=True)
            cv2.imwrite(str(OUT / f"bench_{a.label}_phantom_{i+1}.png"), vis)
    if ph_list:
        print(f"\n  false shots ({len(ph_list)}), frame pair / target mm / "
              "size / strength:")
        for n, x, y, d, pk in ph_list:
            print(f"    pair {n}: x {x:+7.1f}  y {y:+7.1f}  "
                  f"{d:5.1f} px  peak {pk:5.1f}")
        print(f"  difference images -> {OUT}/bench_{a.label}_phantom_*.png")
    if off_card:
        print(f"\n  ({off_card} change(s) off the card ignored, as `shot` "
              "ignores them)")

    persp = all(i.get("perspective") for i in infos)
    ring_rms = float(np.mean([i.get("rms_mm", np.nan) for i in infos]))
    edge_rms = float(np.mean([i.get("edge_rms_px", np.nan) for i in infos]))

    OUT.mkdir(exist_ok=True)
    snap = OUT / f"bench_{a.label}.png"
    cv2.imwrite(str(snap), np.clip(frames[0], 0, 255).astype(np.uint8))
    row = {"when": datetime.now().strftime("%Y-%m-%d %H:%M"), "label": a.label,
           "rounds": a.rounds, "frames": a.frames,
           "view_deg": round(ref.tilt_deg, 1), "perspective": persp,
           "geom_noise_mm": round(geom_mean, 4),
           "geom_worst_mm": round(geom_worst, 4),
           "centre_sd_mm": round(cen_sd, 4),
           "phantoms_max": max(phantoms) if phantoms else 0,
           "ring_rms_mm": round(ring_rms, 3), "edge_rms_px": round(edge_rms, 2),
           "pix_noise": round(pix_noise, 2), "sat_pct": round(sat, 2),
           "paper": round(paper), "black": round(black),
           "contrast": round(paper - black)}
    path = OUT / "bench.csv"
    new = not path.exists()
    with open(path, "a", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(row))
        if new:
            w.writeheader()
        w.writerow(row)

    with open(path) as f:
        rows = list(csv.DictReader(f))
    cols = [("label", 14, "label"), ("geom_noise_mm", 10, "geom mm"),
            ("geom_worst_mm", 10, "worst mm"), ("phantoms_max", 8, "phantom"),
            ("ring_rms_mm", 8, "ring mm"), ("edge_rms_px", 8, "edge px"),
            ("pix_noise", 8, "noise"), ("sat_pct", 7, "sat%"),
            ("contrast", 8, "contrast")]
    print("\n  " + "".join(f"{h:>{w}}" for _, w, h in cols))
    print("  " + "-" * sum(w for _, w, _ in cols))
    for r in rows:
        print("  " + "".join(f"{r[k]:>{w}}" for k, w, _ in cols))
    dec = decimal_step_mm(spec) / 4.0
    print(f"\n  budget {dec:.2f} mm. geom/worst = score noise from the geometry "
          "alone; phantom = false shots `shot` would report.")
    print(f"  frame -> {snap}\n")


def _keep_on_card(holes, tf, spec):
    """Drop detections outside the card outline. A change in the background
    (a glint on a shiny object, something moving) is never a shot. Returns
    (kept, number dropped)."""
    kept = [h for h in holes if on_card(*tf.to_mm(h["xw"], h["yw"]), spec)]
    return kept, len(holes) - len(kept)


def cmd_listen(a):
    """
    Measure what the camera's microphone hears when a shot lands, so the
    audio trigger threshold is set from real numbers. Fire a few shots while
    it runs; each sharp sound is printed as it happens.
    """
    import audio
    OUT.mkdir(exist_ok=True)
    wav = OUT / "listen.wav"
    print(f"\n  listening on '{a.mic}' for {a.seconds:.0f} s (Ctrl+C to stop).")
    print("  Stay quiet for the first 3 s while the room's noise floor is "
          "measured,")
    print("  then fire a few shots. Each sharp sound is printed below.\n")
    print(f"  {'#':>3} {'time s':>8} {'gap ms':>8} {'peak dBFS':>10} "
          f"{'above floor':>12} {'length ms':>10}")

    def show(e, evs):
        gap = (e["t"] - evs[-2]["t"]) * 1000.0 if len(evs) > 1 else float("nan")
        print(f"  {len(evs):>3} {e['t']:>8.2f} {gap:>8.0f} {e['peak_db']:>10.1f} "
              f"{e['over_db']:>10.1f} dB {e['len_ms']:>10.0f}", flush=True)

    events, floor_db, x, rate = audio.listen(a.seconds, a.mic, a.ratio_db,
                                             on_event=show, wav_path=wav)
    if len(x) == 0 or float(np.abs(x).max()) == 0.0:
        print("\n  ! The microphone returned pure silence. On macOS that "
              "usually means")
        print("    no permission: System Settings > Privacy & Security > "
              "Microphone,")
        print("    allow VS Code / Terminal, then fully restart it.")
        return
    print(f"\n  noise floor {floor_db:.1f} dBFS, loudest sample "
          f"{audio.dbfs(np.abs(x).max()):.1f} dBFS, "
          f"{len(events)} event(s) over +{a.ratio_db:.0f} dB")
    print(f"  recording -> {wav}\n")


def _scale_tf(tf, k):
    """Rescale a TargetFrame found on a downscaled image back to full size."""
    return tf.scaled(k)


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
    print("    view    camera may sit off to the side; ring fit RMS want <= 0.25 mm")
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
            rms = info.get("edge_rms_px", float("nan")) / ds

            if info.get("perspective"):
                rr = info["rms_mm"]
                lines.append((f"view ~{tf.tilt_deg:.0f} deg   perspective fit "
                              f"{len(info['rings'])} rings  RMS {rr:.2f} mm",
                              GOOD if rr <= 0.25 else WARN))
            else:
                lines.append(("ELLIPSE ONLY - perspective fit failed: "
                              f"{info.get('reason', '')[:40]}",
                              WARN if tf.axis_ratio >= 0.99 else BAD))
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

            over = offscreen_sides(tf, ring_radius_mm(spec, 1), gray.shape)
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
                        ("live", cmd_live, "live view with real-time geometry"),
                        ("bench", cmd_bench, "measure the rig for A/B lighting "
                                             "comparisons"),
                        ("listen", cmd_listen, "measure what the camera mic "
                                               "hears when a shot lands")):
        s = sub.add_parser(name, help=h)
        s.set_defaults(func=fn)
        s.add_argument("--target", choices=sorted(SPECS), default="pistol")
        s.add_argument("--device", type=int, default=0)
        s.add_argument("--frames", type=int, default=8)
        s.add_argument("--expect", type=int, default=None)
        s.add_argument("--image", default=None,
                       help="score a saved image instead of the camera")
        if name == "shot":
            s.add_argument("--before", default=None,
                           help="replay: baseline frame (with --image = after)")
            s.add_argument("--count", type=int, default=1,
                           help="shots in a row; asks for your by-eye call "
                                "after each")
            s.add_argument("--ask", action="store_true",
                           help="ask for your by-eye call on a single shot")
            s.add_argument("--rule", choices=("pellet", "visible", "gauge"),
                           default="pellet",
                           help="touch rule: pellet's own mark, tears ignored "
                                "(default, matches the shooter's calls); "
                                "visible hole incl. tears; or official gauge")
            s.add_argument("--auto", action="store_true",
                           help="hands-free: the camera mic triggers each shot")
            s.add_argument("--mic", default="Kiyo")
            # 2026-11: shots +48..+65 dB, 204-370 ms; other sounds (card
            # change, magnet clang) up to +57 dB but at most 160 ms
            s.add_argument("--trigger-db", type=float, default=45.0,
                           help="auto: loudness over the room floor")
            s.add_argument("--trigger-ms", type=float, default=180.0,
                           help="auto: minimum sound length")
            s.add_argument("--settle", type=float, default=1.0,
                           help="auto: seconds after impact before capture")
            s.add_argument("--verbose", action="store_true",
                           help="auto: print every sound and full reports")
            s.add_argument("--no-speak", dest="speak", action="store_false",
                           help="auto: no sounds / spoken scores")
            s.add_argument("--watch", type=float, default=2.0,
                           help="auto: seconds between card-change checks")
            s.add_argument("--speaker", action="store_true",
                           help="auto: announcements play from a speaker near "
                                "the camera - ignore the mic while they play")
            s.add_argument("--per-card", type=int, default=None,
                           help="auto: announce 'change the card' after this "
                                "many shots on a card")
        s.add_argument("--roi", action="store_true",
                       help="crop using calib.json's ROI (default: full frame)")
        s.add_argument("--every", type=int, default=3,
                       help="live: solve geometry every Nth frame")
        s.add_argument("--detect-scale", type=float, default=0.5,
                       help="live: downscale factor for the solve")
        if name == "listen":
            s.add_argument("--seconds", type=float, default=60.0)
            s.add_argument("--mic", default="Kiyo",
                           help="input device name to match")
            s.add_argument("--ratio-db", type=float, default=20.0,
                           help="event threshold above the noise floor")
        if name == "bench":
            s.add_argument("--label", required=True,
                           help="condition name, e.g. light-on / light-off")
            s.add_argument("--rounds", type=int, default=10)
            s.set_defaults(frames=1)
    a = p.parse_args()
    a.func(a)


if __name__ == "__main__":
    main()
