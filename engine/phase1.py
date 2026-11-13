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
import os
import sys
from pathlib import Path

import cv2
import numpy as np

import target0
from geometry import (find_target_frame, refine_bull_ellipse, fit_perspective,
                      flatten_illumination, draw_rings, offscreen_sides)
from scoring import SPECS, PISTOL, score_xy, decimal_step_mm, on_card
import course as course_mod
import voicelines

HERE = Path(__file__).resolve().parent

# The sound trigger, measured 2026-11: shots +48..+65 dB over the room floor and
# 204-370 ms long; other sounds (card change, magnet clang) up to +57 dB but at
# most 160 ms. Shared by `shot --auto` and `listen` (so the web app's sound check
# says exactly what would trigger).
# A shot's sound must be this far over the room. Set for the LAPTOP's mic at
# the firing line hearing the GUN (2026-11-12, 20 shots: +67 to +74 dB; cocking,
# loading and coughs +46 to +57, other sounds up to +59.7, one card change
# +63.6 - harmless, it finds no hole and says nothing). The Kiyo's mic at the
# target heard IMPACTS as quiet as +48.5: use --trigger-db 45 for that.
TRIGGER_DB = 62.0
TRIGGER_MS = 180.0
# After a sound trigger with no new hole yet, look this many more times, this
# far apart, for a frame that arrived late (the Pi stream lags 0.2-1.6 s).
LATE_LOOKS = 3
LATE_LOOK_S = 0.6
# A camera find this soon after a sound whose capture showed no hole is that
# sound's shot - heard AND seen ("sound_camera"; the Pi stream's lag).
# A new hole seen by a quick camera check is scored from a frame taken at least
# this long after it: the second sighting (2026-11-12, was a whole check later).
SECOND_LOOK_S = 0.5
HEARD_WINDOW_S = 20.0   # the camera check found them 10-15 s later in a real session
# Where shots, logs and pictures are saved. SPOTTER_OUT overrides it, so a demo
# replay (web: bin/rails spotter:demo) never writes into the real shot log.
OUT = Path(os.environ["SPOTTER_OUT"]) if os.environ.get("SPOTTER_OUT") else HERE / "out"


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
            print(f"                true center is {pinfo['centre_shift_px']:.1f} px "
                  f"from the ellipse center")
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
                print("    will be wrong away from the center. Check the ring "
                      "lines are visible.")
        print(f"  center      : ({tf.cx:.2f}, {tf.cy:.2f}) px")
        print(f"  scale       : {tf.mm_per_px:.5f} mm/px at the center "
              f"({1/tf.mm_per_px:.1f} px/mm)")
        from scoring import ring_radius_mm as _rr
        over = offscreen_sides(tf, _rr(spec, 1), gray.shape)
        if over:
            print(f"\n  ! The ring-1 scoring edge runs outside the frame on the "
                  f"{', '.join(over)}.")
            print("    Shots landing there cannot be seen. Recenter the card.")
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
    if a.json:
        return _locate_json(a, spec)
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


def cmd_pinpoint(a):
    """
    `pinpoint --image AFTER [--before BEFORE] --px X Y --out DIR`: the web app's
    "score it by hand" for a capture the engine could not score. The shooter
    tapped the hole at pixel (X, Y) of the saved after frame; the target is
    located in THAT frame (perspective + lens, as for every shot) and the tap
    becomes target mm. Writes the straightened close-ups (closeup_before.jpg /
    closeup_after.jpg, as a scored shot has) to DIR. One JSON line on stdout:
    {"found": true, "x_mm", "y_mm", "closeup": {...}} or {"found": false, "reason"}.
    """
    import contextlib
    import io
    import json
    from report import closeup, jpeg
    spec = SPECS[a.target]

    def frame(path):
        img = cv2.imread(path, cv2.IMREAD_GRAYSCALE)
        if img is None:
            return None, None
        img = img.astype(np.float32)
        with contextlib.redirect_stdout(io.StringIO()):
            return img, establish(img, spec, verbose=False)[0]

    after, tf = frame(a.image)
    if tf is None:
        print(json.dumps({"found": False, "reason": "could not locate the target in the picture"}))
        return
    x_mm, y_mm = (float(v) for v in tf.to_mm(a.px[0], a.px[1]))
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    centre = (x_mm, y_mm)
    (out / "closeup_after.jpg").write_bytes(jpeg(closeup(after, tf, centre)))
    if a.before:
        before, tf_b = frame(a.before)
        if tf_b is not None:
            (out / "closeup_before.jpg").write_bytes(jpeg(closeup(before, tf_b, centre)))
    print(json.dumps({"found": True, "x_mm": round(x_mm, 3), "y_mm": round(y_mm, 3),
                      "closeup": {"centre": [round(x_mm, 3), round(y_mm, 3)],
                                  "px_per_mm": 20.0, "size_px": 480}}))


def _locate_json(a, spec):
    """
    `locate --json [--overlay PATH]`: the camera check for the web app's rig
    setup page. One JSON object on stdout - is the target found, how well the
    rings fit, focus, view angle, card flatness, which edges ring 1 runs off,
    and the lighting - plus the ring overlay saved to PATH (or out/).
    """
    import contextlib
    import io
    import json
    from scoring import ring_radius_mm
    if a.watch:
        return _locate_watch(a, spec)
    with contextlib.redirect_stdout(io.StringIO()):
        gray = acquire(a)
    path = Path(a.overlay) if a.overlay else OUT / "p1_locate.png"
    print(json.dumps(_locate_result(gray, spec, a.target, path)))


def _locate_watch(a, spec):
    """
    `locate --json --watch SECONDS`: the live camera check. Keeps the camera
    open and prints a fresh result about once a second (with `seq`), saving
    the overlay each time, so the shooter can aim and focus while watching the
    verdicts change. Stops after SECONDS or on SIGINT (Ctrl+C / the web app's
    Stop) with a final {"type": "end"} line.
    """
    import contextlib
    import io
    import json
    import time
    path = Path(a.overlay) if a.overlay else OUT / "p1_locate.png"
    print(json.dumps({"type": "start", "camera": str(a.device),
                      "seconds": a.watch}), flush=True)
    with contextlib.redirect_stdout(io.StringIO()):
        try:
            cam = _LiveCamera(a.device)
        except SystemExit as e:
            cam, err = None, str(e).strip()
    if cam is None:
        print(json.dumps({"type": "error", "message": err}), flush=True)
        return
    t0, seq = time.time(), 0
    try:
        while time.time() - t0 < a.watch:
            tick = time.time()
            try:
                gray = cam.grab(2)
            except CameraLost as e:
                print(json.dumps({"type": "error", "message": str(e)}), flush=True)
                time.sleep(1.0)
                continue
            seq += 1
            r = _locate_result(gray, spec, a.target, path)
            r.update(type="result", seq=seq, t=round(time.time() - t0, 1),
                     remaining=round(max(0.0, a.watch - (time.time() - t0))),
                     solve_ms=round((time.time() - tick) * 1000))
            print(json.dumps(r), flush=True)
            time.sleep(max(0.0, 1.0 - (time.time() - tick)))
    except KeyboardInterrupt:
        pass
    finally:
        cam.close()
    print(json.dumps({"type": "end", "results": seq}), flush=True)


def _locate_result(gray, spec, target, path):
    """One camera check: measurements as a dict, ring overlay saved to path
    (atomically: written aside then renamed, so a reader never gets half)."""
    import contextlib
    import io
    import os
    from scoring import ring_radius_mm
    result = {"found": False}
    with contextlib.redirect_stdout(io.StringIO()):
        g8 = np.clip(gray, 0, 255).astype(np.uint8)
        result.update(width=int(gray.shape[1]), height=int(gray.shape[0]),
                      brightness=round(float(g8.mean()), 1),
                      saturated_pct=round(float((g8 >= 254).mean() * 100), 2),
                      # rises as the picture gets sharper: a live focusing aid
                      sharpness=round(float(cv2.Laplacian(g8, cv2.CV_64F).var()), 1))
        tf, info = establish(gray, spec, verbose=False)
    vis = cv2.cvtColor(g8, cv2.COLOR_GRAY2BGR)
    if tf is None:
        result["reason"] = info.get("reason", "the aiming mark was not found")
    else:
        draw_rings(vis, tf, spec)
        fw = info.get("flat_worst_mm")
        result.update(
            found=True, target=target,
            view_deg=round(tf.tilt_deg, 1),
            edge_rms_px=round(info["edge_rms_px"], 2) if info.get("refined") else None,
            perspective=bool(info.get("perspective")),
            perspective_reason=None if info.get("perspective") else info.get("reason"),
            ring_rms_mm=round(info["rms_mm"], 3) if info.get("rms_mm") is not None else None,
            rings=len(info.get("rings", {})),
            flat_worst_mm=round(fw, 2) if fw is not None else None,
            flat_worst_at=info.get("flat_worst_at"),
            mm_per_px=round(tf.mm_per_px, 4),
            centre_px=[round(tf.cx, 1), round(tf.cy, 1)],
            ring1_offscreen=offscreen_sides(tf, ring_radius_mm(spec, 1), gray.shape))
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.stem + ".partial" + path.suffix)
    cv2.imwrite(str(tmp), vis)
    os.replace(tmp, path)
    result["overlay"] = str(path)
    return result


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
                prior=(), geo=None):
    """
    Score what changed between a baseline and an after frame. Returns a result
    dict, or None if the target could not be found in the after frame.
    tf, geo: the after frame's geometry if the caller already solved it
    (establish's two results), so it isn't solved twice.
    """
    from geometry import register, frame_shift_mm, new_light

    if verbose:
        print(f"\n{spec.name}")
    geo = geo or {}
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
    h0 = hd[0]
    f = h0["fit"]
    cx0, cy0 = tf.to_mm(h0["xw"], h0["yw"])
    # Every position estimate and the geometry's health, for the web app's review
    # page and as training data for the planned model (docs/engine-events.md).
    estimates = {"centroid": [round(cx0, 3), round(cy0, 3)],
                 "circle_fit": {"x": f["x_mm"], "y": f["y_mm"], "ok": f["ok"],
                                "arc_deg": round(f["arc_deg"], 1)},
                 "visible_edge_r_mm": h0.get("vis_r_edge")}
    region = {"dia_mm": round(h0["diam_px"] * tf.local_mm_per_px(h0["xw"], h0["yw"]), 2),
              "circularity": round(h0["circ"], 3), "peak": round(h0["peak"], 1)}
    return {"n": n, "found": True, "row": best, "fit_ok": f["ok"],
            "arc_deg": f["arc_deg"], "regions": len(hd), "tf": tf,
            "geo_rms": geo.get("rms_mm"), "geo_persp": geo.get("perspective"),
            "estimates": estimates, "region": region,
            "geometry": {"ring_rms_mm": geo.get("rms_mm"),
                         "perspective": geo.get("perspective"),
                         "k1": geo.get("k1"), "k2": geo.get("k2")}}


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


class CameraLost(RuntimeError):
    """The camera (usually the Pi's stream) stopped delivering frames."""


class _LiveCamera:
    """
    Keep the camera open and read continuously in a background thread, so a
    capture returns FRESH frames immediately instead of reopening the device
    (seconds) or getting stale buffered frames.
    """

    LOST_AFTER_S = 3.0      # no frames this long = connection lost
    RETRY_EVERY_S = 2.0

    def __init__(self, device, w=1920, h=1080):
        import threading
        import time
        self.device = device
        self.cap = target0.open_camera(device, w, h)
        self.lock = threading.Lock()
        self.frame, self.seq = None, 0
        self.last_frame_at = time.time()
        self.lost = False
        self.running = True
        self.th = threading.Thread(target=self._run, daemon=True)
        self.th.start()

    def _run(self):
        """Read forever. A stream from the Pi can drop (Wi-Fi, power): after
        LOST_AFTER_S without a frame, say so and keep reopening until it is
        back, so a session survives an outage instead of dying."""
        import time
        while self.running:
            ok, bgr = self.cap.read()
            now = time.time()
            if ok:
                with self.lock:
                    self.frame, self.seq = bgr, self.seq + 1
                    self.last_frame_at = now
                if self.lost:
                    self.lost = False
                    print("  -- camera connection restored --", flush=True)
                continue
            if now - self.last_frame_at < self.LOST_AFTER_S:
                time.sleep(0.05)
                continue
            if not self.lost:
                self.lost = True
                print(f"  -- camera connection LOST ({self.device}); "
                      "reconnecting... --", flush=True)
            try:
                self.cap.release()
            except Exception:
                pass
            time.sleep(self.RETRY_EVERY_S)
            if self.running:
                self.cap = cv2.VideoCapture(self.device)

    def grab(self, n=8, timeout=5.0):
        """Average the next n frames that arrive AFTER this call. Raises
        CameraLost at once while the connection is down."""
        import time
        if self.lost:
            raise CameraLost(f"no frames from {self.device}")
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
            raise CameraLost(f"no frames from {self.device} in {timeout:.0f} s")
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


class KokoroVoice:
    """
    The announcer voice (engine/voice/speak.py, Kokoro on its own Python 3.13):
    one helper process per session, asked for each announcement as a WAV with
    real pauses between its pieces (voicelines). None of this may stop an
    announcement: if the helper is not set up, dies, or is slow, `render`
    returns None and the caller falls back to macOS `say`.
    """
    DIR = Path(__file__).resolve().parent / "voice"
    TIMEOUT_S = 12.0          # a new piece takes ~1.3 s; an all-new line ~6 s

    def __init__(self, voice):
        import subprocess
        import threading
        self.voice, self.proc, self.lock = voice, None, threading.Lock()
        python = self.DIR / ".venv" / "bin" / "python"
        if not python.exists() or not (self.DIR / "models" / "kokoro-v1.0.onnx").exists():
            print(f"  voice: Kokoro not set up (engine/voice/setup.sh) - using the Mac voice",
                  flush=True)
            return
        try:
            self.proc = subprocess.Popen(
                [str(python), str(self.DIR / "speak.py"), "serve", "--voice", voice],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                text=True, bufsize=1)
        except OSError as e:
            print(f"  voice: could not start Kokoro ({e}) - using the Mac voice", flush=True)
            return
        print(f"  voice: Kokoro '{voice}' (pieces not yet cached are made on "
              "first use, ~1.3 s each, and filled in meanwhile)", flush=True)

    def _line(self, timeout):
        import select
        r, _, _ = select.select([self.proc.stdout], [], [], timeout)
        return self.proc.stdout.readline() if r else None

    def render(self, text):
        """The announcement as a WAV path, or None (then use `say`)."""
        import json
        if self.proc is None or self.proc.poll() is not None:
            return None
        import time
        with self.lock:
            try:
                if not getattr(self, "ready", False):       # model loading, once
                    self.ready = bool(self._line(self.TIMEOUT_S))
                self.seq = getattr(self, "seq", 0) + 1
                self.proc.stdin.write(json.dumps({"id": self.seq, "text": text}) + "\n")
                self.proc.stdin.flush()
                deadline = time.time() + self.TIMEOUT_S
                while (left := deadline - time.time()) > 0:
                    line = self._line(left)
                    if not line:                 # timed out, or the helper died
                        break
                    reply = json.loads(line)
                    if reply.get("id") == self.seq:   # skip a late answer to an
                        return reply.get("wav")       # earlier, timed-out request
                print("  voice: Kokoro slow - this one in the Mac voice", flush=True)
                return None
            except (OSError, ValueError):
                return None

    def close(self):
        if self.proc is not None and self.proc.poll() is None:
            try:
                self.proc.stdin.close()
                self.proc.wait(timeout=2)
            except Exception:
                self.proc.kill()


class _Speech:
    """One announcement playing: its tone at once, then the voice (Kokoro if
    it can, else `say`). poll() is None while it plays, like a Popen, so the
    announcement mute (--speaker) knows exactly when it ended. Announcements
    play one at a time (the range officer's "start" never talks over a shot
    call); kind "ro" has no tone - the command is the signal."""

    import threading as _threading
    LOCK = _threading.Lock()

    def __init__(self, kind, text, voice):
        import threading
        self.done = False
        threading.Thread(target=self._run, args=(kind, text, voice), daemon=True).start()

    def _run(self, kind, text, voice):
        with _Speech.LOCK:
            self._play(kind, text, voice)

    def _play(self, kind, text, voice):
        import subprocess
        try:
            tone = (subprocess.Popen(["afplay", SOUNDS[kind]], stdout=subprocess.DEVNULL,
                                     stderr=subprocess.DEVNULL) if kind in SOUNDS else None)
            wav = voice.render(text) if (voice and text) else None   # while the tone plays
            if tone is not None:
                tone.wait()
            if wav:
                subprocess.run(["afplay", wav], stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL)
            elif text:
                subprocess.run(["say", text], stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL)
        except OSError:
            pass
        finally:
            self.done = True

    def poll(self):
        return 0 if self.done else None


def _announce(kind, text, enabled=True, voice=None):
    """
    Tell the shooter at the firing line what happened, without looking: a
    distinct sound per outcome (ok / check / fail), then the result spoken -
    by the Kokoro voice the shooter picked (`voice`, a KokoroVoice), with
    clear pauses between its pieces, or macOS `say`. Non-blocking. Returns
    {start, proc, end} so the caller can ignore its OWN announcement on the
    trigger microphone for as long as it actually plays: the laptop speaker
    near the mic measured +52.6 dB for the fail tone - over the shot
    threshold - so an estimated mute window let it retrigger itself.
    """
    import time
    if not enabled:
        return None
    return {"start": time.time(), "proc": _Speech(kind, text, voice), "end": None}


class _WebSpeech:
    """An announcement handed to the web app to play (shot --auto --announce
    web): the engine can't hear when the browser finishes, so poll() goes by an
    estimate - enough for the range officer to pace its commands."""
    PIECE_S = 0.75

    def __init__(self, sentences, gaps):
        import time
        pieces = sum(len(s["pieces"]) for s in sentences)
        commas = sum(max(len(s["pieces"]) - 1, 0) for s in sentences)
        self.end = (time.time() + pieces * self.PIECE_S + commas * gaps["comma"]
                    + max(len(sentences) - 1, 0) * gaps["sentence"])

    def poll(self):
        import time
        return 0 if time.time() >= self.end else None


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
    right, right, low right, low, low left, left, high left - or center for an
    inner ten. Target +y is up (image-up through the centre, see
    geometry.fit_perspective)."""
    import math
    if inner_ten or math.hypot(x_mm, y_mm) < 1.0:
        return "center"
    names = ["right", "high right", "high", "high left",
             "left", "low left", "low", "low right"]
    ang = math.degrees(math.atan2(y_mm, x_mm)) % 360.0
    return names[int(((ang + 22.5) % 360.0) // 45.0)]


def _spoken_direction(r):
    """The direction as said: "shot low", with how far out in ring steps (so
    the same for pistol and rifle): "a touch" in the 10 and 9 rings, plain in
    the 8 and 7, "well" in the 6 or worse. Each phrase is one voice piece
    (voicelines.DIRECTION_PHRASES): "low" said on its own sounded wrong."""
    d = _direction(r["x_mm"], r["y_mm"], r["inner_ten"])
    if d == "center":
        return d
    ring = r["integer"]
    degree = "a touch " if ring >= 9 else ("" if ring >= 7 else "well ")
    return f"shot {degree}{d}"


def _spoken(r, res):
    """The result as a short phrase for `say`."""
    words = (f"{r['decimal']:.1f}, " + _spoken_direction(r)
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


def _fit_ok(info, rms_mm=0.4, points=1000):
    """A geometry fit good enough to be a BASELINE: the full perspective + lens
    model, from enough ring points, fitting them closely. 2026-11-12, camera
    moved below the card: the baseline taken as a card went up fitted badly (the
    inner rings drawn low and squashed for the whole card) while every frame a
    moment later fitted all 10 rings to 0.08 mm from ~3550 points. Limits set
    on all 328 saved frames: genuine fits <= 0.32 mm (a card torn by many
    holes) from >= 3071 points; misfits have no perspective model, 0-132
    points, >= 1.8 mm."""
    return bool(info) and bool(info.get("perspective")) and \
        info.get("rms_mm", 9.9) <= rms_mm and info.get("points", 0) >= points


def _same_view(tf, ref, shift_mm=15.0, scale=0.15):
    """
    Is a frame's fitted geometry plausibly the SAME view as the baseline's? A
    second after the shot the camera hasn't moved; a fit that jumps tens of mm
    or changes scale by tens of % is a MISFIT, not movement. 2026-11-12: two
    real shots on the aiming mark's rim (the bright hole notching the black's
    outline) solved 63-69 mm off at ~-88% scale; that made the frames read 45%
    "changed", the movement guard rejected both shots ("not scored, view
    moving"), and the camera check scored them seconds later. With the
    baseline's geometry they scored within 0.1 mm of the later scores. Limits
    far from both: across all 144 real before/after pairs the largest genuine
    difference was 4.2 mm / 4% (shot 074, a real small view change, which keeps
    its own geometry).
    """
    import math
    if tf is None or ref is None:
        return False
    moved = math.hypot(tf.cx - ref.cx, tf.cy - ref.cy) * ref.mm_per_px
    return moved <= shift_mm and abs(tf.mm_per_px / ref.mm_per_px - 1.0) <= scale


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


def _load_hole_model(a):
    """The learned hole locator (holemodel.py), in SHADOW mode: its estimate is
    reported with each shot, the rules still score. --hole-model PATH, or
    out/ml/model/hole.onnx when it exists; 'none' turns it off. Never fatal."""
    choice = getattr(a, "hole_model", None) or os.environ.get("SPOTTER_HOLE_MODEL")
    if choice == "none":
        return None
    try:
        import holemodel
        m = holemodel.HoleModel.load(choice)
    except Exception as e:                      # noqa: BLE001 - scoring must go on
        print(f"  hole model: could not load ({e}) - rules only", flush=True)
        return None
    if m is not None:
        print(f"  hole model: {m.version} (trained on {m.meta.get('trained_on', '?')} "
              "called shots), shadow mode", flush=True)
    return m


def _hole_model_estimate(model, before_jpeg, after_jpeg, centre, spec, a):
    from scoring import PELLET_MM, PELLET_MARK_MM
    try:
        mark = PELLET_MM if getattr(a, "rule", "pellet") == "gauge" else PELLET_MARK_MM
        return model.estimate(before_jpeg, after_jpeg, centre, spec, mark)
    except Exception as e:                      # noqa: BLE001 - shadow only
        print(f"  hole model failed: {e}", flush=True)
        return None


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
    # --mic none: camera only. No sound trigger; the camera check every
    # --watch seconds finds each shot (2-4 s instead of ~1 s). For a camera
    # with no usable microphone, e.g. a stream from the Pi.
    camera_only = a.mic is not None and a.mic.lower() == "none"   # not no --mic at all
    if camera_only:
        idx, info = None, {"name": "no microphone (camera only)",
                           "default_samplerate": 16000, "max_input_channels": 1}
    else:
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

    def locate_info(img):
        with contextlib.redirect_stdout(io.StringIO()):
            return establish(img, spec, verbose=False)

    def baseline(first=None, tries=5):
        """A frame and its geometry to compare shots against, VERIFIED (_fit_ok):
        up to `tries` frames, the first that fits well - else the best that
        fitted at all (frame, tf), or (frame, None) if the target wasn't found."""
        best = None
        for i in range(tries):
            frame = first if (i == 0 and first is not None) else cam.grab(a.frames)
            tf, info = locate_info(frame)
            if tf is not None and _fit_ok(info):
                if i:
                    print(f"  (baseline: a good fit on try {i + 1})", flush=True)
                return frame, tf
            if tf is not None:
                score = (bool(info.get("perspective")), -info.get("rms_mm", 9.9))
                if best is None or score > best[0]:
                    best = (score, frame, tf)
            time.sleep(0.3)
        if best is not None:
            print("  ! baseline: no frame fitted well - using the best; the rings "
                  "may be off (\"Re-find target\" tries again)", flush=True)
            return best[1], best[2]
        return frame, None

    print(f"\n  AUTO: listening on '{info['name']}', camera {a.device}. "
          "Ctrl+C to finish.")
    print(f"  sound trigger: > +{a.trigger_db:.0f} dB over the room, "
          f">= {a.trigger_ms:.0f} ms; capture {a.settle:.1f} s after impact.")
    print(f"  camera check every {a.watch:.0f} s: catches shots without a "
          "sound, card changes, people in view.")
    cam = _LiveCamera(a.device)
    st = {"prior": [], "scored": 0, "card_no": 1, "ann": [],
          "last_fail_say": -1e9, "dirty": False}
    # "Re-find the target" (the web app's button, after the camera was jostled):
    # SIGUSR2 asks for a fresh look - a new baseline from the card as it sits
    # now - taken in the main loop, not in the handler.
    import signal as _signal
    _signal.signal(_signal.SIGUSR2, lambda *_: st.__setitem__("refind", True))
    # The web app sends SIGUSR2 only to an engine that printed this (an older
    # one would be killed by it).
    print("  re-find target: SIGUSR2", flush=True)
    # "Pause scoring" (the web app's button, to change cards without false
    # shots): SIGTSTP pauses - sounds ignored, no camera checks - and SIGCONT
    # resumes with a fresh baseline (same card or new). Ctrl+Z in a terminal
    # pauses too, instead of suspending the process.
    _signal.signal(_signal.SIGTSTP, lambda *_: st.__setitem__("pause", True))
    _signal.signal(_signal.SIGCONT, lambda *_: st.__setitem__("resume", True))
    print("  pause scoring: SIGTSTP / SIGCONT", flush=True)
    # The live picture for the web app's range screen (the engine holds the
    # camera, so it serves it): rings from the current baseline drawn on.
    view_srv = None
    if a.stream_port:
        from liveview import LiveView
        view_srv = LiveView(cam, spec, geometry=lambda: st.get("tf_b")).serve(a.stream_port)
        print(f"  live view: http://127.0.0.1:{a.stream_port}/snapshot.jpg (and /stream)")

    # The web app (web/), when asked: every event below is also posted there.
    rep = None
    if a.report_to:
        import os
        from report import Reporter
        rep = Reporter(a.report_to, target=a.target,
                       rule=getattr(a, "rule", "pellet"),
                       token=os.environ.get("SPOTTER_TOKEN"),
                       session_id=a.session_id)
        print(f"  reporting to {a.report_to} (session {rep.session_id})")

    def emit(type_, data=None, files=None, at=None):
        if rep is not None:
            rep.send(type_, data, files, at)

    def frames(before, after):
        from report import png
        return {"before_image": lambda: ("before.png", png(before), "image/png"),
                "after_image": lambda: ("after.png", png(after), "image/png")}

    hole_model = _load_hole_model(a)

    voice = KokoroVoice(a.voice) if (a.speak and a.voice) else None
    web_speech = getattr(a, "announce", "local") == "web"
    same = object()

    def say(kind, text, plain_kind=same):
        """Announce. `text` is a phrase, or a list of (phrase, diagnostic)
        parts: diagnostic parts (line call, found without a sound...) are left
        out unless the shooter turned diagnostic mode on. `plain_kind` is the
        tone without them (None: nothing to say then).
        --announce web: the web app plays it in the browser (an "announce"
        event, docs/engine-events.md); else it is spoken here, every part."""
        parts = [(text, False)] if isinstance(text, str) else text
        plain_kind = kind if plain_kind is same else plain_kind
        if web_speech:
            gaps = {"sentence": voicelines.SENTENCE_GAP_S, "comma": voicelines.COMMA_GAP_S}
            sentences = [{"pieces": pieces, "diagnostic": diag}
                         for phrase, diag in parts for pieces in voicelines.split(phrase)]
            emit("announce", {"kind": kind, "plain_kind": plain_kind,
                              "sentences": sentences, "gaps": gaps})
            return _WebSpeech(sentences, gaps)
        an = _announce(kind, ". ".join(phrase for phrase, _ in parts), a.speak, voice)
        if an:
            st["ann"].append(an)
            st["ann"][:] = st["ann"][-5:]
        return an["proc"] if an else None

    # The virtual range officer (course.py), for a match or final: its own
    # thread and clock; started at "ready". Practice has none.
    ro = None
    if getattr(a, "course", None):
        import signal
        import datetime

        def phase(info):
            if info.get("ends_at"):
                info = dict(info, ends_at=datetime.datetime.fromtimestamp(
                    info["ends_at"], datetime.timezone.utc).isoformat())
            print(f"  RO: {info['phase']} - {info['label']}", flush=True)
            emit("course", info)

        ro = course_mod.Runner(course_mod.COURSES[a.course],
                               speak=lambda text: say("ro", text), phase=phase)
        signal.signal(signal.SIGUSR1, lambda *_: ro.skip())   # "Start match"

    def score_now(label, trigger="camera", sound_db=None, at=None, after=None):
        """Capture the after frame (or use `after`, one a camera check just
        took), score it against the baseline, report.
        Returns True if a shot was scored (and the baseline moved on)."""
        at = at if at is not None else time.time()
        heard = st.get("heard")
        if trigger == "camera" and heard and time.time() - heard["t"] < HEARD_WINDOW_S:
            # the sound came first (its capture was too early): its time is the
            # shot's, exact, and it was not "found without a sound"
            trigger, at, sound_db = "sound_camera", heard["t"], heard["db"]
            label = f"camera, after a sound +{heard['db']:.0f} dB"
        if after is None:
            after = cam.grab(a.frames)
        n = _next_shot_number()
        print(f"  ===== shot {n:03d}  ({label})")
        # A real shot changes a hole-sized patch. If large parts of the card
        # changed, something moved (the 2026-11 phantom: a magnet's clang
        # while the shooter, in the baseline frame, was mounting the card).
        # Solved ONCE here and handed to _score_pair, which used to solve the
        # same frame again (~0.5-1 s per shot on a slow laptop).
        tf_a, info_a = locate_info(after)
        geo_a = info_a                       # the fit's health, for the geometry warning
        if tf_a is not None and not _fit_ok(info_a) and st["tf_b"] is not None:
            print("  ! the after frame fitted poorly - using the baseline's "
                  "geometry", flush=True)
            tf_a, geo_a = st["tf_b"], None
        if tf_a is not None and not _same_view(tf_a, st["tf_b"]):
            # A misfit (see _same_view): the camera didn't move in a second, so
            # the baseline's geometry holds. Real movement still shows - the
            # frames then differ under that geometry, and the guard below says so.
            print("  ! the after frame's geometry is off (a hole on the aiming "
                  "mark's edge?) - using the baseline's", flush=True)
            tf_a, geo_a = st["tf_b"], None
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
            emit("unscored", {"reason": "view changed too much (person / card "
                              "moving)", "trigger": trigger},
                 frames(st["before"], after), at)
            # Not announced (the shooter, 2026-11-12: false triggers made a
            # spoken "not scored" annoying); logged and reported above.
            if trigger == "sound":
                st["heard"] = {"t": at, "db": sound_db or 0.0}
            return False
        with silent():
            res = _score_pair(a, spec, st["before"], st["tf_b"], after, n,
                              tf=tf_a, geo=geo_a, verbose=a.verbose,
                              prior=st["prior"])
        if res is None:
            time.sleep(0.5)                  # something in the way - retry
            after = cam.grab(a.frames)
            with silent():
                res = _score_pair(a, spec, st["before"], st["tf_b"], after, n,
                                  verbose=a.verbose, prior=st["prior"])
        # Over the Pi's Wi-Fi a frame arrives 0.2-1.6 s after it was TAKEN
        # (measured 2026-11-12), so the first capture after a sound can still
        # show the card before the pellet landed: "not scored", then the camera
        # check found it seconds later. Look again before giving up - no wait
        # at all when the first capture already has the hole.
        if trigger == "sound":
            for _ in range(LATE_LOOKS):
                if res is not None and res.get("found"):
                    break
                time.sleep(LATE_LOOK_S)
                after = cam.grab(a.frames)
                tf_l, info_l = locate_info(after)
                if tf_l is None or _scene_moving(st["before"], st["tf_b"], after, tf_l, spec):
                    break                    # someone in view: not a late frame
                geo_l = info_l
                if not _fit_ok(info_l) or not _same_view(tf_l, st["tf_b"]):
                    tf_l, geo_l = st["tf_b"], None
                with silent():
                    res = _score_pair(a, spec, st["before"], st["tf_b"], after, n,
                                      tf=tf_l, geo=geo_l, verbose=a.verbose,
                                      prior=st["prior"])
                if res is not None and res.get("found"):
                    print("  (found on a later frame - the stream was behind)", flush=True)
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
            emit("unscored", {"reason": why, "trigger": trigger},
                 frames(st["before"], after), at)
            # Not announced - see the movement case above.
            if trigger == "sound":
                st["heard"] = {"t": at, "db": sound_db or 0.0}
            return False
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
            say("check", [("geometry warning, consider a fresh card", True)], plain_kind=None)
        elif res.get("geo_rms") is not None and res["geo_rms"] > 0.25:
            print(f"  ! geometry: ring fit {res['geo_rms']:.2f} mm (usually "
                  "~0.1-0.15) - the card is getting torn up\n", flush=True)
        words, flags = _spoken(r, res)
        if trigger in ("camera", "final_check") and not camera_only:
            # a missed sound is worth a look; with no microphone it is normal
            flags = ["found without a sound"] + flags
        # flags: why the shot is worth a look - DIAGNOSTIC (the shooter can
        # turn them off); a penalty below is scoring, always said.
        _log_shot(res)
        st["prior"].append((r["x_mm"], r["y_mm"]))
        k = len(st["prior"])                 # shot number ON THIS CARD
        full = a.per_card and k == a.per_card
        # In a match or final: sighter or competition shot, and in time or not
        # (the impact time; a camera-found shot was SEEN late, so its window
        # gets the camera check's slack).
        cls = (ro.classify(at, grace=0.0 if trigger in ("sound", "sound_camera") else 2 * a.watch)
               if ro is not None else None)
        penalty = cls.get("penalty") if cls else None
        # Lead with the shot's number, so a missed shot is noticed at once
        # ("shot five" when you expected six): on this card in practice, in
        # the match in a match or final; a sighter is "sighter".
        lead = ("sighter" if cls and cls["stage"] == "sighter" else
                f"shot {cls['number']}" if cls else f"shot {k}")
        # The score first (what the shooter is waiting for), then why it is
        # worth a look. The "check" tone already marks it, so no spoken "check"
        # (alone, it sounded wrong).
        parts = [(lead, False), (words, False)]
        if flags:
            parts.append((", ".join(flags), True))
        if penalty:
            parts.append((f"{penalty}, scores zero", False))
        if full:
            parts += [(f"that's {a.per_card}", False), ("new card please", False)]
        say("check" if flags or penalty else "ok", parts,
            plain_kind="check" if penalty else "ok")
        if full:
            print(f"  -- {a.per_card} shots on card {st['card_no']}: change the "
                  "card (it will say 'card off', then 'new card, ready') --\n",
                  flush=True)
        if rep is not None:
            from report import closeup, jpeg
            b_img, b_tf, a_img, a_tf = st["before"], st["tf_b"], after, res["tf"]
            centre = (r["x_mm"], r["y_mm"])
            est = dict(res["estimates"],
                       closeup={"centre": [round(centre[0], 3), round(centre[1], 3)],
                                "px_per_mm": 20.0, "size_px": 480})
            files = frames(b_img, a_img)
            if hole_model is not None:
                # SHADOW MODE: the learned locator reads the same close-ups the
                # web app stores (so they are made here, once); its estimate is
                # reported beside the rules', which still score the shot.
                cb, ca = jpeg(closeup(b_img, b_tf, centre)), jpeg(closeup(a_img, a_tf, centre))
                files["closeup_before"] = lambda: ("closeup_before.jpg", cb, "image/jpeg")
                files["closeup_after"] = lambda: ("closeup_after.jpg", ca, "image/jpeg")
                m = _hole_model_estimate(hole_model, cb, ca, centre, spec, a)
                if m:
                    est["model"] = m
                    print(f"  model (shadow): {m['decimal']:.1f} ring {m['ring']} "
                          f"(P {m['p_ring']:.2f}, +-{m['sigma_mm']:.2f} mm, "
                          f"{np.hypot(m['x_mm'] - centre[0], m['y_mm'] - centre[1]):.2f} mm from the rules')",
                          flush=True)
            else:
                files["closeup_before"] = lambda: ("closeup_before.jpg", jpeg(
                    closeup(b_img, b_tf, centre)), "image/jpeg")
                files["closeup_after"] = lambda: ("closeup_after.jpg", jpeg(
                    closeup(a_img, a_tf, centre)), "image/jpeg")
            emit("shot", {
                "engine_shot_id": f"{n:03d}", "trigger": trigger,
                "sound_db": sound_db, "card_shot": k,
                "x_mm": round(r["x_mm"], 3), "y_mm": round(r["y_mm"], 3),
                "r_mm": round(r["r_mm"], 3), "decimal": r["decimal"],
                "ring": r["integer"], "inner_ten": bool(r["inner_ten"]),
                "rule": r.get("rule"), "line_mm": round(r["line_mm"], 3),
                "line_call": bool(r["line_call"]),
                "ambiguous": bool(r["ambiguous"]), "overlap": bool(r["overlap"]),
                "estimates": est, "region": res["region"],
                "geometry": res["geometry"], "course": cls,
                # seconds from the sound to the score (announced, reported);
                # none for a camera find - nothing marks when that shot landed
                "detect_s": (round(time.time() - at, 2)
                             if trigger in ("sound", "sound_camera") else None)}, None, at)
            # its pictures follow in the picture lane (report.Reporter): the
            # score and the range screen never wait for them
            emit("shot_images", {"engine_shot_id": f"{n:03d}"}, files, at)
        # The shot's frames, kept for replay: written AFTER the announcement
        # and the report, so the shooter isn't waiting on two full-size PNGs.
        for tag, img in (("before", st["before"]), ("after", after)):
            cv2.imwrite(str(sdir / f"{n:03d}_{tag}.png"),
                        np.clip(img, 0, 255).astype(np.uint8))
        st["scored"] += 1
        st.pop("heard", None)
        st["before"], st["tf_b"] = after, res["tf"]
        return True

    def _resume(path):
        """A CONTINUED session (`--resume FILE`, written by the web app): the
        last card's number, its holes in target mm and the last shot's after
        picture. Same card on the target (its holes are still there, as after a
        card change: _same_card) -> carry on counting it and checking overlaps
        against its holes; else the next card. Returns "same card", "new card"
        or None (not a continued session)."""
        if not path:
            return None
        import json
        r = json.loads(Path(path).read_text())
        st["card_no"] = int(r.get("card") or 1)
        holes = [tuple(h) for h in r.get("holes") or []]
        same = True                          # an empty card, or nothing to compare
        old = cv2.imread(r["image"], cv2.IMREAD_GRAYSCALE) if r.get("image") else None
        if holes and old is not None:
            old = old.astype(np.float32)
            old_tf = locate(old)
            if old_tf is not None:
                same = _same_card(old, old_tf, st["before"], st["tf_b"], holes)
        if same:
            st["prior"] = holes
            print(f"  continuing card {st['card_no']} ({len(holes)} shot(s) on it)\n", flush=True)
            return "same card"
        st["card_no"] += 1
        print(f"  continuing on a new card (card {st['card_no']})\n", flush=True)
        return "new card"

    try:
        time.sleep(1.0)                          # let exposure settle
        st["before"], st["tf_b"] = baseline()
        if st["tf_b"] is None:
            print("  could not locate the target - check framing and lighting")
            return
        print("  baseline taken. Ready - fire when you like.\n")
        resumed = _resume(getattr(a, "resume", None))
        emit("session_started", {"target": a.target,
                                 "rule": getattr(a, "rule", "pellet"),
                                 "course": getattr(a, "course", None)})
        if resumed == "new card":
            emit("new_card")
            say("ready", "new card, ready")
        else:
            emit("ready")
            say("ready", "same card, ready" if resumed == "same card" else "ready")
        if ro is not None:
            ro.start()

        det = audio.EventDetector(rate, ratio_db=min(20.0, a.trigger_db))
        with (contextlib.nullcontext() if camera_only else
              sd.InputStream(device=idx, channels=min(2, info["max_input_channels"]),
                             samplerate=rate, blocksize=int(rate * 0.02),
                             callback=cb)):
            t_audio0 = time.time()
            last_trig = -1e9
            w = {"card_on": True, "misses": 0, "still": 0, "cand": None,
                 "last": None, "next": time.time() + a.watch}

            def camera_lost():
                """Say so (once a minute at most); keep the baseline. Shots
                fired meanwhile are found by the camera check once it's back."""
                if time.time() - st.get("lost_said", -1e9) > 60.0:
                    st["lost_said"] = time.time()
                    print("  ! camera not delivering frames - holding the "
                          "baseline until it is back\n", flush=True)
                    say("fail", "camera connection lost")

            def new_hole(frame, tf_now):
                """Position (mm) of the strongest hole-sized new region against
                the baseline, or None."""
                reg = (st["before"] if tf_now is st["tf_b"] else
                       register(st["before"], st["tf_b"], tf_now, frame.shape))
                d = new_light(frame, reg)
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
                # ONE new frame: averaging buys nothing, and over the Pi's stream
                # (~4 fps arrive) waiting for 2 made a check ~1.3 s, not ~0.7 s
                frame = cam.grab(1)
                t_frame = time.time()
                # QUIET VIEW, FAST (2026-11-12): with the focus locked the card
                # sits still to ~1-3 um, so the baseline's own fit holds - no
                # ~0.35 s re-fit and no registration, ~0.4 s a check instead of
                # ~0.8. Anything unusual (movement, card off) takes the full
                # check below, on this same frame.
                if w["card_on"] and not st["dirty"] and w["last"] is not None \
                        and st.get("tf_b") is not None and not _scene_moving(
                            w["last"][0], w["last"][1], frame, st["tf_b"], spec):
                    w["last"] = (frame, st["tf_b"])
                    pos = new_hole(frame, st["tf_b"])
                    ghosts = st.get("ghosts", (None, []))
                    ghosts = ghosts[1] if ghosts[0] is st["before"] else []
                    if pos is None or any(np.hypot(pos[0] - g[0], pos[1] - g[1]) < 3
                                          for g in ghosts):
                        w["cand"] = None
                        return
                    # A new hole: score it from the NEXT frame with a full fit -
                    # that is the second, independent sighting (a one-off glare
                    # is gone by then and scores nothing). If it finds nothing,
                    # this spot is a ghost until the baseline changes, so a
                    # false alarm can't fire again and again.
                    w["cand"] = None
                    # the second sighting at least 0.5 s after the first (a
                    # brief glint or fleck must not pass as a hole)
                    time.sleep(max(0.0, SECOND_LOOK_S - (time.time() - t_frame)))
                    last_trig = time.time() - t_audio0   # mute its late sound
                    base = st["before"]
                    if not score_now("camera - no sound heard", trigger="camera"):
                        st["ghosts"] = (base, ghosts + [pos])
                    return
                tf_now = locate(frame)
                if tf_now is None:
                    w["still"], w["cand"], w["last"] = 0, None, None
                    w["misses"] += 1
                    if w["card_on"] and w["misses"] >= 2:
                        w["card_on"] = False
                        print("  -- target out of view (card off?) --", flush=True)
                        say("info", "card off")
                        emit("card_off")
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
                        if score_now("camera - no sound heard", trigger="camera"):
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
                    new, tf_new = baseline()
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
                        emit("ready")
                        say("ready", "ready")
                    return
                if not w["card_on"]:
                    # card back: wait for TWO still checks, then a baseline
                    w["still"] += 1
                    if w["still"] < 2:
                        return
                    w["card_on"], w["still"], st["dirty"] = True, 0, False
                    new, tf_new = baseline()
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
                        emit("new_card")
                    print(f"  -- {msg} (card {st['card_no']}, new baseline) --\n",
                          flush=True)
                    say("ready", msg)
                    if msg != "new card, ready":
                        emit("ready")
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
                    # the frame that confirmed it is fresh: score that one
                    score_now("camera - no sound heard", trigger="camera", after=frame)
                else:
                    w["cand"] = pos

            def refind():
                """A fresh baseline from the card as it sits now (the shooter
                bumped the camera): the rings follow it. A shot fired since the
                last baseline and not yet scored would be absorbed - the button
                is for between shots.
                Says "please wait" at once (finding a good fit takes a second or
                two), then "ready" - or "card off" if the card isn't in view."""
                say("info", "please wait")
                frame, tf_new = baseline()
                if tf_new is None:
                    print("  re-find: the target isn't in view - not changed\n", flush=True)
                    say("info", "card off")
                    return
                st["before"], st["tf_b"] = frame, tf_new
                w["cand"], w["last"], w["still"] = None, None, 0
                print("  -- re-found the target: new baseline. Ready --\n", flush=True)
                emit("ready")
                say("ready", "ready")

            def pause():
                """Stop scoring (the shooter is changing the card): sounds are
                ignored and the camera checks stop until resume()."""
                st["paused"] = True
                print("  -- scoring PAUSED (change the card; nothing is scored) --\n",
                      flush=True)
                emit("paused")
                say("info", "scoring paused")

            def resume():
                """Scoring again: a fresh verified baseline from the card as it
                sits now, and the card-change decision the camera check makes
                when a card goes back up (_same_card). On the SAME card, a hole
                against the old baseline is a shot fired before or during the
                pause that nothing scored: score it first, rather than letting
                the new baseline swallow it."""
                nonlocal last_trig
                st["paused"] = False
                say("info", "please wait")
                # card "off" until the new baseline is in: if the camera drops
                # out meanwhile, the card-back flow takes over, not the old baseline
                w.update(card_on=False, misses=0, still=0, cand=None, last=None,
                         next=time.time() + a.watch)
                st["dirty"] = False
                frame, tf_new = baseline()
                if tf_new is None:
                    # no card in view yet: the camera check takes it from here
                    # ("card back" once it is up and still)
                    print("  -- scoring resumed: the target isn't in view yet --\n",
                          flush=True)
                    emit("card_off")
                    say("info", "card off")
                    return
                w["card_on"] = True
                old_ok = st.get("tf_b") is not None
                same = (not st["prior"] or not old_ok or
                        _same_card(st["before"], st["tf_b"], frame, tf_new, st["prior"]))
                if same and old_ok and new_hole(frame, tf_new) is not None:
                    last_trig = time.time() - t_audio0
                    if score_now("camera - no sound heard", trigger="camera", after=frame):
                        print("  -- scoring resumed (a hole from before the pause "
                              "was scored first) --\n", flush=True)
                        return
                st["before"], st["tf_b"] = frame, tf_new
                if same:
                    msg = "same card, ready" if st["prior"] else "ready"
                    emit("ready")
                else:
                    st["prior"].clear()
                    st["card_no"] += 1
                    msg = "new card, ready"
                    emit("new_card")
                print(f"  -- scoring resumed: {msg} (card {st['card_no']}, "
                      "new baseline) --\n", flush=True)
                say("ready", msg)

            while True:
                try:
                    blk = q.get(timeout=0.2)
                except queue.Empty:
                    blk = None
                _track_announcements(st["ann"])
                # "The results are final": end the session as Stop would, with
                # its final check for an unscored hole.
                if ro is not None and ro.done and time.time() - ro.finished > 3.0:
                    print("\n  course complete.", flush=True)
                    raise KeyboardInterrupt
                if st.pop("pause", False) and not st.get("paused"):
                    pause()
                if st.pop("resume", False) and st.get("paused"):
                    try:
                        resume()
                    except CameraLost:
                        camera_lost()
                if st.pop("refind", False) and not st.get("paused"):
                    try:
                        refind()
                    except CameraLost:
                        camera_lost()
                if st.get("paused"):
                    pass        # no camera checks: the card is being changed
                elif time.time() >= w["next"] and q.qsize() < 5:
                    w["next"] = time.time() + a.watch
                    try:
                        watch()
                    except CameraLost:
                        camera_lost()
                if blk is None:
                    continue
                for e in det.feed(blk):
                    # Muting our own announcements only matters if they come
                    # out of a speaker near the camera (--speaker). With
                    # earbuds it only risked muting real shots.
                    why = ("paused" if st.get("paused") else
                           "own announcement"
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
                    try:
                        if score_now(f"sound +{e['over_db']:.0f} dB",
                                     trigger="sound",
                                     sound_db=round(e["over_db"], 1),
                                     at=t_audio0 + e["t"]):
                            w["cand"] = None
                    except CameraLost:
                        # the baseline is kept, so when the camera is back the
                        # camera check still finds this shot's hole
                        camera_lost()
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
                    score_now("camera - found at the end of the session",
                              trigger="final_check")
                else:
                    print("  nothing unscored.", flush=True)
        except KeyboardInterrupt:
            pass
    finally:
        if view_srv is not None:
            view_srv.shutdown()
        if voice is not None:
            voice.close()
        cam.close()
        if rep is not None:
            emit("session_ended")
            rep.close()
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
    if a.json:
        return _listen_json(a, audio, wav)
    print(f"\n  listening on '{a.mic or 'the default microphone'}' for "
          f"{a.seconds:.0f} s (Ctrl+C to stop).")
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


def _listen_json(a, audio, wav):
    """
    `listen --json`: the sound check for the web app's rig setup page. One JSON
    line per event as it happens - start (with the trigger settings), each
    sound (marked would_trigger against TRIGGER_DB / TRIGGER_MS, exactly as
    `shot --auto` decides), and end (noise floor, silence = no permission).
    """
    import json

    def emit(obj):
        print(json.dumps(obj), flush=True)

    emit({"type": "start", "mic": a.mic, "seconds": a.seconds,
          "trigger_db": TRIGGER_DB, "trigger_ms": TRIGGER_MS})

    def level(elapsed, level_db, floor_db):
        emit({"type": "level", "t": round(elapsed, 2),
              "remaining": round(max(0.0, a.seconds - elapsed)),
              "level_dbfs": round(level_db, 1),
              "floor_dbfs": round(floor_db, 1) if floor_db is not None else None,
              "over_db": round(level_db - floor_db, 1) if floor_db is not None else None})

    def show(e, evs):
        gap = (e["t"] - evs[-2]["t"]) * 1000.0 if len(evs) > 1 else None
        length = max(0.0, e["len_ms"])
        emit({"type": "sound", "n": len(evs), "t": round(e["t"], 2),
              "gap_ms": round(gap) if gap is not None else None,
              "peak_dbfs": round(e["peak_db"], 1), "over_db": round(e["over_db"], 1),
              "len_ms": round(length),
              "would_trigger": e["over_db"] >= TRIGGER_DB and length >= TRIGGER_MS})

    try:
        events, floor_db, x, rate = audio.listen(a.seconds, a.mic, a.ratio_db,
                                                 on_event=show, wav_path=wav,
                                                 on_level=level)
    except SystemExit as e:                       # no such microphone
        emit({"type": "error", "message": str(e)})
        return
    silent = len(x) == 0 or float(np.abs(x).max()) == 0.0
    emit({"type": "end", "silent": silent, "events": len(events),
          "floor_dbfs": round(floor_db, 1) if floor_db is not None else None,
          "loudest_dbfs": None if silent else round(audio.dbfs(np.abs(x).max()), 1)})


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
    print("    offset  want ~0,0       (recenter the card)")
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


def _stop_signals():
    """
    Make Ctrl+C (SIGINT) and a polite terminate (SIGTERM) both raise
    KeyboardInterrupt, so every stop runs the clean shutdown (`shot --auto`'s
    final check and session_ended; `listen`'s summary).

    Installed explicitly because a process started in the background from a
    script inherits SIGINT as IGNORED, and Python keeps an inherited ignore:
    the web app's Stop then silently did nothing (found 2026-11 when the demo
    task, itself started in the background, launched the engine).
    """
    import signal

    def interrupt(signum, frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGINT, signal.default_int_handler)
    signal.signal(signal.SIGTERM, interrupt)


def main():
    _stop_signals()
    p = argparse.ArgumentParser(description="Phase 1 - self-locating scorer")
    sub = p.add_subparsers(dest="cmd", required=True)
    pp = sub.add_parser("pinpoint", help="a tapped pixel of a saved frame -> target mm "
                                         "(the web app's hand-scoring of a capture)")
    pp.set_defaults(func=cmd_pinpoint)
    pp.add_argument("--target", choices=sorted(SPECS), default="pistol")
    pp.add_argument("--image", required=True, help="the after frame (PNG)")
    pp.add_argument("--before", default=None, help="the before frame, for its close-up")
    pp.add_argument("--px", type=float, nargs=2, required=True, metavar=("X", "Y"))
    pp.add_argument("--out", required=True, help="where to write the close-ups")
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
        s.add_argument("--device", type=target0.parse_device, default=0,
                       help="camera index, or a stream URL from the Pi at the "
                            "target (http://<pi>:8080/stream)")
        # Frames averaged per capture. 1: averaging buys nothing (1 and 16
        # frames measured identical; jitter ~1 um on the Pi rig), and over the
        # Pi's Wi-Fi stream (~4 fps reach the laptop) waiting for 8 new frames
        # took 2-3 s per shot, 1 frame 0.24 s (2026-11-12).
        s.add_argument("--frames", type=int, default=1)
        s.add_argument("--expect", type=int, default=None)
        s.add_argument("--image", default=None,
                       help="score a saved image instead of the camera")
        if name == "locate":
            s.add_argument("--json", action="store_true",
                           help="print one JSON result (the web app's camera check)")
            s.add_argument("--overlay", default=None,
                           help="with --json: where to save the ring overlay")
            s.add_argument("--watch", type=float, default=0,
                           help="with --json: keep checking about once a second "
                                "for this many seconds (the live camera check)")
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
            s.add_argument("--hole-model", default=None,
                           help="learned hole locator, SHADOW mode (reported, not "
                                "scored): an .onnx path, or 'none'; default "
                                "out/ml/model/hole.onnx if it exists")
            s.add_argument("--mic", default=None,
                           help="auto: microphone name to match (default: the "
                                "computer's default input; 'none' = camera only)")
            # 2026-11: shots +48..+65 dB, 204-370 ms; other sounds (card
            # change, magnet clang) up to +57 dB but at most 160 ms
            s.add_argument("--trigger-db", type=float, default=TRIGGER_DB,
                           help="auto: loudness over the room floor")
            s.add_argument("--trigger-ms", type=float, default=TRIGGER_MS,
                           help="auto: minimum sound length")
            s.add_argument("--settle", type=float, default=1.0,
                           help="auto: seconds after impact before capture")
            s.add_argument("--verbose", action="store_true",
                           help="auto: print every sound and full reports")
            s.add_argument("--no-speak", dest="speak", action="store_false",
                           help="auto: no sounds / spoken scores")
            # 1 s (was 2, 2026-11-12): with no mic at the target the camera check
            # finds EVERY shot (two sightings), so this sets how quickly; a check
            # takes ~0.7 s, so faster would only run them back to back and make
            # a sound wait for the check in progress.
            s.add_argument("--watch", type=float, default=1.0,
                           help="auto: seconds between camera checks (card off/on, "
                                "movement, a new hole without a sound)")
            s.add_argument("--session-id", default=None,
                           help="auto: the web app's id for this session (it "
                                "passes this, and SPOTTER_TOKEN, when it starts "
                                "the engine)")
            s.add_argument("--report-to", default=None, metavar="URL",
                           help="auto: also post every event to the web app at "
                                "URL, e.g. http://localhost:3000 "
                                "(docs/engine-events.md)")
            s.add_argument("--announce", choices=["local", "web"], default="local",
                           help="auto: speak here (local), or hand each "
                                "announcement to the web app to play in the "
                                "browser (web; needs --report-to)")
            s.add_argument("--speaker", action="store_true",
                           help="auto: announcements play from a speaker near "
                                "the camera - ignore the mic while they play")
            import voicelines
            s.add_argument("--voice", default=None, choices=list(voicelines.VOICES),
                           metavar="VOICE",
                           help="auto: announce with this Kokoro voice, e.g. "
                                "af_heart (engine/voice; default: the Mac voice)")
            s.add_argument("--stream-port", type=int, default=0,
                           help="auto: serve the live camera picture, rings "
                                "drawn on, on 127.0.0.1:PORT (the web app's "
                                "range screen shows it)")
            s.add_argument("--resume", default=None,
                           help="auto: continue a session - a JSON file with the "
                                "last card's number, holes and last picture")
            s.add_argument("--per-card", type=int, default=None,
                           help="auto: announce 'new card please' after this "
                                "many shots on a card")
            s.add_argument("--course", default=None, choices=sorted(course_mod.COURSES),
                           help="auto: a course of fire run by the virtual range "
                                "officer (course.py): match, final, ranking. "
                                "SIGUSR1 ends a match's sighting time early. "
                                "Default: practice (no clock)")
        s.add_argument("--roi", action="store_true",
                       help="crop using calib.json's ROI (default: full frame)")
        s.add_argument("--every", type=int, default=3,
                       help="live: solve geometry every Nth frame")
        s.add_argument("--detect-scale", type=float, default=0.5,
                       help="live: downscale factor for the solve")
        if name == "listen":
            s.add_argument("--json", action="store_true",
                           help="one JSON line per event (the web app's sound check)")
            s.add_argument("--seconds", type=float, default=60.0)
            s.add_argument("--mic", default=None,
                           help="input device name to match (default: the "
                                "computer's default input)")
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
