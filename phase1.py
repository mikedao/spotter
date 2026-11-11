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


def report(holes, tf, spec, vis=None, quiet=False):
    rows = []
    for h in holes:
        if h.get("x_mm") is not None:          # circle-fitted pellet centre
            x_mm, y_mm = h["x_mm"], h["y_mm"]
        else:
            x_mm, y_mm = tf.to_mm(h["xw"], h["yw"])
        s = score_xy(x_mm, y_mm, spec)
        # On torn paper the circle fit and the region centroid can disagree
        # by 1-2 mm, and neither is reliably right (2026-11: one real shot each
        # way). When they land in different rings, the ring is not known.
        # Flag when the span between the two estimates (plus the line-call
        # margin) crosses a ring line: then the ring itself is not known.
        s["ambiguous"] = False
        if h.get("x_mm") is not None:
            from scoring import ring_radius_mm, LINE_CALL_MM
            sc = score_xy(*tf.to_mm(h["xw"], h["yw"]), spec)
            s["alt_decimal"] = sc["decimal"]
            lo = min(s["r_edge_mm"], sc["r_edge_mm"]) - LINE_CALL_MM
            hi = max(s["r_edge_mm"], sc["r_edge_mm"]) + LINE_CALL_MM
            s["ambiguous"] = any(lo <= ring_radius_mm(spec, k) <= hi
                                 for k in range(1, 11))
        s["check"] = s["line_call"] or s["ambiguous"]
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
            flag += f"  RING UNCERTAIN ({s['alt_decimal']} by centroid) - check"
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


def _shot_once(a, spec):
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
    return _score_pair(a, spec, before, tf_b, after, n)


def _next_shot_number():
    sd = OUT / "shots"
    sd.mkdir(parents=True, exist_ok=True)
    return 1 + max([int(p.name[:3]) for p in sd.glob("[0-9][0-9][0-9]_after.png")]
                   or [0])


def _score_pair(a, spec, before, tf_b, after, n, tf=None, verbose=True):
    """
    Score what changed between a baseline and an after frame. Returns a result
    dict, or None if the target could not be found in the after frame.
    """
    from geometry import register, frame_shift_mm, new_light

    if verbose:
        print(f"\n{spec.name}")
    if tf is None:
        tf, _ = establish(after, spec, verbose=verbose)
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
    rows = report(hd, tf, spec, vis)

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
             "check by eye" if best["ambiguous"] else ""))
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
            "arc_deg": f["arc_deg"], "regions": len(hd), "tf": tf}


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

    for i in range(a.count):
        if a.count > 1:
            print(f"\n========== shot {i + 1} of {a.count} ==========")
        res = _shot_once(a, spec)
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


def _shot_auto(a, spec):
    """
    Hands-free: the camera's microphone triggers each capture.

    A shot is a loud, sustained impulse on the mic (measured 2026-11: shots at
    -1 to 0 dBFS, +59 to +65 dB over the room floor, 280-370 ms of ringing;
    the loudest non-shot was +43 dB). After a trigger we wait for the paper
    and trap to settle (a faint secondary sound follows ~0.7 s later), take
    the after frame, score it, and it becomes the next baseline.

    A false trigger is harmless: if vision finds no new hole the shot is
    discarded and the baseline is kept, so a hole can never be absorbed into
    the baseline without being scored.
    """
    import queue
    import time
    import sounddevice as sd
    import audio

    # Each trigger compares the frame just before a shot with the frame just
    # after it, so there is exactly one new hole per comparison.
    if a.expect is None:
        a.expect = 1
    idx, info = audio.find_input(a.mic)
    rate = int(info["default_samplerate"])
    q = queue.Queue()

    def cb(indata, frames, t, status):
        q.put(indata.mean(axis=1).astype(np.float32).copy())

    print(f"\n  AUTO: listening on '{info['name']}', camera {a.device}. "
          "Ctrl+C to finish.")
    print(f"  trigger: > +{a.trigger_db:.0f} dB over the room, "
          f">= {a.trigger_ms:.0f} ms long; capture {a.settle:.1f} s after impact.")
    cam = _LiveCamera(a.device)
    scored = 0
    try:
        time.sleep(1.0)                          # let exposure settle
        before = cam.grab(a.frames)
        tf_b, _ = establish(before, spec, verbose=False)
        if tf_b is None:
            print("  could not locate the target - check framing and lighting")
            return
        print("  baseline taken. Ready - fire when you like.\n")

        det = audio.EventDetector(rate, ratio_db=min(20.0, a.trigger_db))
        with sd.InputStream(device=idx, channels=min(2, info["max_input_channels"]),
                            samplerate=rate, blocksize=int(rate * 0.02),
                            callback=cb):
            t_audio0 = time.time()
            last_trig = -1e9
            while True:
                try:
                    blk = q.get(timeout=1.0)
                except queue.Empty:
                    continue
                for e in det.feed(blk):
                    why = ("too quiet" if e["over_db"] < a.trigger_db else
                           "too short" if e["len_ms"] < a.trigger_ms else
                           "echo of last shot" if e["t"] - last_trig < 2.0
                           else None)
                    if a.verbose:
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
                    after = cam.grab(a.frames)
                    n = _next_shot_number()
                    print(f"  ===== shot {n:03d}  (sound +{e['over_db']:.0f} dB)")
                    import contextlib
                    import io
                    quiet = (contextlib.nullcontext() if a.verbose
                             else contextlib.redirect_stdout(io.StringIO()))
                    with quiet:
                        res = _score_pair(a, spec, before, tf_b, after, n,
                                          verbose=a.verbose)
                    if res is None or not res.get("found"):
                        print("  sound, but no new hole on the card - ignored "
                              "(baseline kept)\n")
                        continue
                    sdir = OUT / "shots"
                    for tag, img in (("before", before), ("after", after)):
                        cv2.imwrite(str(sdir / f"{n:03d}_{tag}.png"),
                                    np.clip(img, 0, 255).astype(np.uint8))
                    r = res["row"]
                    print(f"  >>> {r['decimal']}   ring {r['integer']}   "
                          f"x {r['x_mm']:+.1f}  y {r['y_mm']:+.1f} mm"
                          + ("   INNER TEN" if r["inner_ten"] else "")
                          + ("" if res["fit_ok"] else "   (centroid - check)")
                          + (f"   LINE CALL ({r['line_mm']:.2f} mm) - check by eye"
                             if r["line_call"] else "")
                          + (f"   RING UNCERTAIN (or {r['alt_decimal']}) - check by eye"
                             if r["ambiguous"] else "")
                          + "\n", flush=True)
                    _log_shot(res)
                    scored += 1
                    # Audio that queued up while scoring is NOT discarded: a
                    # second shot fired during scoring must still be caught.
                    # The trap's ringing is handled by the 2 s echo window.
                    before, tf_b = after, res["tf"]
    except KeyboardInterrupt:
        pass
    finally:
        cam.close()
    print(f"\n  session: {scored} shot(s) scored")
    _print_log(max(scored, 1))


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
            s.add_argument("--auto", action="store_true",
                           help="hands-free: the camera mic triggers each shot")
            s.add_argument("--mic", default="Kiyo")
            s.add_argument("--trigger-db", type=float, default=52.0,
                           help="auto: loudness over the room floor")
            s.add_argument("--trigger-ms", type=float, default=100.0,
                           help="auto: minimum sound length")
            s.add_argument("--settle", type=float, default=1.0,
                           help="auto: seconds after impact before capture")
            s.add_argument("--verbose", action="store_true",
                           help="auto: print every sound and full reports")
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
