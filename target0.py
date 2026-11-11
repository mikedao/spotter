#!/usr/bin/env python3
"""
Phase 0 feasibility probe for camera-based shot detection.

Answers three questions, in order:
  1. Can this camera resolve a hole sharply at close range?   -> preview
  2. How many mm is one pixel?                                -> calibrate
  3. How much does a detected hole centre wander when
     NOTHING has changed?  (the noise floor)                  -> jitter
  4. Can it find a NEW hole, including an overlapping one?    -> detect

Usage:
  ./target0.py preview
  ./target0.py calibrate
  ./target0.py jitter
  ./target0.py detect
"""
import argparse
import json
import sys
import time
from pathlib import Path

import cv2
import numpy as np

HERE = Path(__file__).resolve().parent
OUT = HERE / "out"
CALIB_PATH = HERE / "calib.json"

# ISSF 10m geometry. "decimal step" is the RADIUS change per 0.1 ring, which
# is what the measurement actually has to resolve. We want error comfortably
# below a quarter of that step.
# ring_mm is the DIAMETER step per ring. Air pistol steps 16mm, not 8mm:
# its black mark is ring 7 (59.5mm) and the outer ring is 155.5mm.
TARGETS = {
    "pistol": {"ring_mm": 16.0, "ten_mm": 11.5, "black_mm": 59.5, "outer_mm": 155.5},
    "rifle":  {"ring_mm": 5.0,  "ten_mm": 0.5,  "black_mm": 30.5, "outer_mm": 45.5},
}
DEFAULT_TARGET = "pistol"

PELLET_MM = 4.5  # nominal .177 hole


def thresholds(target):
    """(decimal_mm, integer_mm) measurement error budgets for a target type."""
    t = TARGETS[target]
    decimal_step = t["ring_mm"] / 2.0 / 10.0   # radius change per 0.1 ring
    integer_step = t["ring_mm"] / 2.0          # radius change per full ring
    return decimal_step / 4.0, integer_step / 4.0


# --------------------------------------------------------------------------
# camera
# --------------------------------------------------------------------------
def open_camera(device: int, width: int, height: int):
    cap = cv2.VideoCapture(device)
    if not cap.isOpened():
        sys.exit(
            f"\nCould not open camera {device}.\n"
            "On macOS the app running this script needs camera permission:\n"
            "  System Settings > Privacy & Security > Camera\n"
            "Enable it for Terminal (or VS Code), then restart that app.\n"
        )
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, width)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height)

    # Try to pin down auto-adjustment. Support is patchy over UVC on macOS;
    # we report what actually stuck rather than assuming.
    cap.set(cv2.CAP_PROP_AUTOFOCUS, 0)
    cap.set(cv2.CAP_PROP_AUTO_EXPOSURE, 0.25)  # 0.25 = manual on many drivers
    cap.set(cv2.CAP_PROP_AUTO_WB, 0)

    for _ in range(10):  # let the pipeline settle
        cap.read()

    aw = cap.get(cv2.CAP_PROP_FRAME_WIDTH)
    ah = cap.get(cv2.CAP_PROP_FRAME_HEIGHT)
    print(f"camera {device}: {int(aw)}x{int(ah)}")
    if (int(aw), int(ah)) != (width, height):
        print(f"  note: asked for {width}x{height}, driver gave {int(aw)}x{int(ah)}")
    print(f"  autofocus={cap.get(cv2.CAP_PROP_AUTOFOCUS)} "
          f"auto_exposure={cap.get(cv2.CAP_PROP_AUTO_EXPOSURE)} "
          f"auto_wb={cap.get(cv2.CAP_PROP_AUTO_WB)}")
    return cap


def grab_gray(cap, n_frames: int):
    """Average n_frames into one float32 greyscale image (noise reduction)."""
    acc = None
    last_bgr = None
    got = 0
    for _ in range(n_frames * 3):  # allow for dropped frames
        ok, bgr = cap.read()
        if not ok:
            continue
        last_bgr = bgr
        g = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY).astype(np.float32)
        acc = g if acc is None else acc + g
        got += 1
        if got >= n_frames:
            break
    if acc is None:
        sys.exit("No frames read from camera.")
    return acc / got, last_bgr


# --------------------------------------------------------------------------
# calibration file
# --------------------------------------------------------------------------
def load_calib():
    if not CALIB_PATH.exists():
        sys.exit("No calib.json. Run:  ./target0.py calibrate")
    return json.loads(CALIB_PATH.read_text())


def save_calib(d):
    CALIB_PATH.write_text(json.dumps(d, indent=2))
    print(f"wrote {CALIB_PATH}")


def crop(img, roi):
    x, y, w, h = roi
    return img[y:y + h, x:x + w]


# --------------------------------------------------------------------------
# hole detection
# --------------------------------------------------------------------------
def detect_holes(gray, mm_per_px=None, min_mm=1.5, max_mm=14.0,
                 min_circularity=0.55, max_holes=None, debug_path=None):
    """
    Find small, bright, ROUND features - i.e. holes.

    A plain global threshold fails badly on a real target: the paper is
    brighter than the black bull, so "brighter than average" selects the whole
    paper and its texture fragments into dozens of blobs. Specular glare makes
    it worse.

    So we use a white TOP-HAT first. It keeps features smaller than the
    structuring element and subtracts the local background, which removes both
    the bull/paper step and any large-scale glare gradient. What survives is
    small bright stuff, which is what a hole is. We then demand roundness,
    because paper texture and glare fragments are not round.
    """
    g8 = np.clip(gray, 0, 255).astype(np.uint8)

    # Blur scaled to the HOLE, not a fixed kernel. Paper grain is 1-3 px while
    # a hole is tens of px. Without enough blur, the opening below tracks the
    # local grain minimum and the top-hat reads large everywhere, which makes
    # the noise-based threshold explode past 255 and find nothing.
    hole_px = (PELLET_MM / mm_per_px) if mm_per_px else 28.0
    sigma = max(1.0, hole_px / 8.0)
    g8 = cv2.GaussianBlur(g8, (0, 0), sigma)

    # Structuring element must be comfortably LARGER than a hole.
    k = int(3.0 * hole_px)
    k = max(15, min(k, 199)) | 1  # odd, sane bounds
    se = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k, k))
    top = cv2.morphologyEx(g8, cv2.MORPH_TOPHAT, se)

    # Threshold the top-hat. Otsu works well here because the top-hat image is
    # mostly near zero, but we floor it so faint texture can never qualify.
    med = float(np.median(top))
    mad = float(np.median(np.abs(top - med))) * 1.4826
    thr_val = max(med + 5.0 * mad, 6.0)
    if thr_val > 200:
        # Background is still dominating - nothing can clear this. Say so
        # rather than silently returning zero holes.
        print(f"  WARNING top-hat threshold {thr_val:.0f} exceeds the usable "
              f"range (median {med:.0f}, MAD {mad:.0f}).")
        print("  The background is not being suppressed. Usually too much "
              "paper grain, glare, or a wrong mm/px scale.")
        thr_val = 200.0
    _, mask = cv2.threshold(top, thr_val, 255, cv2.THRESH_BINARY)

    if float(top.max()) < 12:          # nothing stands out from the background
        return [], thr_val, mask

    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))

    if mm_per_px:
        min_area = np.pi * (min_mm / 2.0 / mm_per_px) ** 2
        max_area = np.pi * (max_mm / 2.0 / mm_per_px) ** 2
    else:
        min_area, max_area = 20, 1e9

    n, labels, stats, cents = cv2.connectedComponentsWithStats(mask, connectivity=8)
    topf = top.astype(np.float32)
    holes = []
    for i in range(1, n):
        area = stats[i, cv2.CC_STAT_AREA]
        if not (min_area <= area <= max_area):
            continue
        x, y, w, h = (stats[i, cv2.CC_STAT_LEFT], stats[i, cv2.CC_STAT_TOP],
                      stats[i, cv2.CC_STAT_WIDTH], stats[i, cv2.CC_STAT_HEIGHT])
        sub = (labels[y:y + h, x:x + w] == i).astype(np.uint8)

        # Roundness: 4*pi*A / P^2 is 1.0 for a perfect circle.
        cnts, _ = cv2.findContours(sub, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
        if not cnts:
            continue
        per = cv2.arcLength(max(cnts, key=cv2.contourArea), True)
        if per <= 0:
            continue
        circ = 4.0 * np.pi * area / (per * per)
        if circ < min_circularity:
            continue

        wts = topf[y:y + h, x:x + w] * sub
        tot = wts.sum()
        if tot <= 0:
            continue
        yy, xx = np.mgrid[y:y + h, x:x + w]
        H, W = g8.shape[:2]
        clipped = (x <= 1 or y <= 1 or (x + w) >= W - 1 or (y + h) >= H - 1)
        holes.append({
            "clipped": bool(clipped),
            "xb": float(cents[i][0]), "yb": float(cents[i][1]),
            "xw": float((wts * xx).sum() / tot), "yw": float((wts * yy).sum() / tot),
            "area_px": float(area),
            "diam_px": float(2.0 * np.sqrt(area / np.pi)),
            "circ": float(circ),
            "bbox": (int(x), int(y), int(w), int(h)),
            "peak": float(topf[y:y + h, x:x + w][sub > 0].max()),
            "sat": float((g8[y:y + h, x:x + w][sub > 0] >= 254).mean()),
        })

    # Keep only the strongest candidates when asked.
    if max_holes is not None and len(holes) > max_holes:
        holes.sort(key=lambda d: d["peak"] * d["area_px"], reverse=True)
        holes = holes[:max_holes]

    if debug_path is not None:
        dbg = np.hstack([g8, top, mask])
        cv2.imwrite(str(debug_path), dbg)

    holes.sort(key=lambda d: (d["yb"], d["xb"]))
    return holes, thr_val, mask


def fit_pellet(img, hole, to_mm, r_mm=PELLET_MM / 2.0, iters=400,
               tol_mm=0.12, seed=0):
    """
    Locate the pellet in a hole region by fitting a circle of the pellet's
    KNOWN radius to the round part of its edge, instead of taking the centroid.

    The centroid is wrong whenever the visible region is not a whole pellet
    disc:
      - paper tears: the region is the pellet hole plus a flap ripped along
        one direction, so the centroid is dragged along the tear;
      - overlapping shots: only a crescent is new, and a crescent's centroid
        is not the pellet's centre (measured 0.33 mm at 3 mm separation).
    In both cases only the pellet's own arc is round with radius r_mm.

    The edge is taken at half the region's height (the true edge of a
    blurred step) and fitted in TARGET millimetres via to_mm, because off-axis
    a round hole images as an ellipse. Two edge points fix two candidate
    centres of radius r_mm; the candidate with the most edge points on its
    circle wins (RANSAC), then least squares refines it on those inliers.

    Returns dict(x_mm, y_mm, inliers, arc_deg, ok) - ok False means too little
    round edge was found and the caller should fall back to the centroid.
    """
    H, W = img.shape[:2]
    x0, y0, w, h = hole["bbox"]
    pad = max(6, int(0.5 * max(w, h)))
    xa, ya = max(0, x0 - pad), max(0, y0 - pad)
    xb, yb = min(W, x0 + w + pad), min(H, y0 + h + pad)
    sub = np.asarray(img[ya:yb, xa:xb], np.float32)
    sub = cv2.GaussianBlur(sub, (0, 0), 1.0)
    inner = sub[(y0 - ya):(y0 - ya + h), (x0 - xa):(x0 - xa + w)]
    peak = float(np.percentile(inner, 95))
    bg = float(np.median(sub))
    thr = bg + 0.5 * (peak - bg)
    m = (sub >= thr).astype(np.uint8)
    cnts, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    fail = {"x_mm": None, "y_mm": None, "inliers": 0, "arc_deg": 0.0,
            "ok": False}
    if not cnts:
        return fail
    cx, cy = hole["xw"] - xa, hole["yw"] - ya
    cnt = min(cnts, key=lambda c: abs(cv2.pointPolygonTest(c, (cx, cy), True))
              if cv2.contourArea(c) > 4 else 1e9)
    pts = cnt[:, 0, :].astype(np.float64)
    if len(pts) < 12:
        return fail
    X, Y = to_mm(pts[:, 0] + xa, pts[:, 1] + ya)
    P = np.stack([np.asarray(X), np.asarray(Y)], 1)

    rng = np.random.default_rng(seed)
    best_c, best_n = None, 0
    n = len(P)
    for _ in range(iters):
        i, j = rng.choice(n, 2, replace=False)
        p, q = P[i], P[j]
        d = np.linalg.norm(q - p)
        if d < 0.6 * r_mm or d > 2 * r_mm:
            continue
        mid = 0.5 * (p + q)
        nrm = np.array([-(q - p)[1], (q - p)[0]]) / d
        hgt = np.sqrt(max(r_mm * r_mm - 0.25 * d * d, 0.0))
        for c in (mid + hgt * nrm, mid - hgt * nrm):
            cnt_in = int((np.abs(np.linalg.norm(P - c, axis=1) - r_mm)
                          < tol_mm).sum())
            if cnt_in > best_n:
                best_c, best_n = c, cnt_in
    if best_c is None:
        return fail

    c = best_c.copy()
    for _ in range(10):                       # Gauss-Newton, centre only
        inl = np.abs(np.linalg.norm(P - c, axis=1) - r_mm) < tol_mm
        Q = P[inl]
        if len(Q) < 6:
            break
        v = Q - c
        dist = np.linalg.norm(v, axis=1)
        J = -v / dist[:, None]
        res = dist - r_mm
        step, *_ = np.linalg.lstsq(J, -res, rcond=None)
        c = c + step
        if np.linalg.norm(step) < 1e-5:
            break
    inl = np.abs(np.linalg.norm(P - c, axis=1) - r_mm) < tol_mm
    ang = np.sort(np.degrees(np.arctan2(*(P[inl] - c).T[::-1])) % 360)
    if len(ang) > 1:
        gaps = np.diff(np.concatenate([ang, [ang[0] + 360]]))
        arc = 360.0 - float(gaps.max())
    else:
        arc = 0.0
    return {"x_mm": float(c[0]), "y_mm": float(c[1]),
            "inliers": int(inl.sum()), "arc_deg": arc,
            "ok": bool(inl.sum() >= 12 and arc >= 150.0)}


def visible_edge(diff, hole, to_mm, grow_px=3):
    """
    Radius (target mm) of the VISIBLE hole's point nearest the centre - the
    edge used by the "visible hole" scoring rule, tears included.

    `diff` should be the PLAIN registered difference (after - before): the
    max-filtered one used for detection erodes real hole edges by ~2 px, which
    would bias every call against the shooter. The plain difference carries
    printed-line residue, so it is only read inside the detected region grown
    by grow_px, and cut at 30% of the region's peak (residue is far below that).

    Returns dict(r_edge, x, y of the nearest visible point, pts_mm = the
    visible outline in target mm), or None.
    """
    H, W = diff.shape[:2]
    x0, y0, w, h = hole["bbox"]
    pad = grow_px + 4
    xa, ya = max(0, x0 - pad), max(0, y0 - pad)
    xb, yb = min(W, x0 + w + pad), min(H, y0 + h + pad)
    sub = np.asarray(diff[ya:yb, xa:xb], np.float32)
    core = np.zeros(sub.shape, np.uint8)
    core[(y0 - ya):(y0 - ya + h), (x0 - xa):(x0 - xa + w)] = 1
    peak = float(np.percentile(sub[core > 0], 95))
    if peak <= 0:
        return None
    # 30% of peak, not 50%: where a hole covers a WHITE ring line inside the
    # black, that patch was already bright before, so its difference is only
    # ~100 against a ~225 peak. At 50% the hole lost exactly the part touching
    # the line (shot 005: called 10, scored 9.9). Printed-line residue in the
    # plain difference is ~20-40, still well below 30%.
    m = (sub >= 0.3 * peak).astype(np.uint8)
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    se = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * grow_px + 1,) * 2)
    m &= cv2.dilate(core, se)
    # Every visible fragment inside the detected area counts (torn pieces are
    # part of the visible hole). Picking one connected component made the
    # result jump when the threshold changed which pieces were connected.
    cnts, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    if not cnts:
        return None
    pts = np.concatenate([c[:, 0, :] for c in cnts]).astype(np.float64)
    X, Y = to_mm(pts[:, 0] + xa, pts[:, 1] + ya)
    r = np.hypot(X, Y)
    i = int(np.argmin(r))
    return {"r_edge": float(r[i]), "x": float(X[i]), "y": float(Y[i]),
            "pts_mm": np.stack([np.asarray(X), np.asarray(Y)], 1)}


def match(ref, cand, tol_px):
    """Nearest-neighbour match of cand onto ref; None where unmatched."""
    out = []
    for r in ref:
        best, bd = None, tol_px
        for c in cand:
            d = np.hypot(c["xb"] - r["xb"], c["yb"] - r["yb"])
            if d < bd:
                best, bd = c, d
        out.append(best)
    return out


def annotate(gray, holes, mm_per_px=None):
    img = cv2.cvtColor(np.clip(gray, 0, 255).astype(np.uint8), cv2.COLOR_GRAY2BGR)
    for i, h in enumerate(holes):
        c = (int(round(h["xw"])), int(round(h["yw"])))
        cv2.circle(img, c, int(h["diam_px"] / 2), (0, 255, 0), 1)
        cv2.drawMarker(img, c, (0, 0, 255), cv2.MARKER_CROSS, 11, 1)
        lab = f"{i}"
        if mm_per_px:
            lab += f" {h['diam_px'] * mm_per_px:.1f}mm"
        cv2.putText(img, lab, (c[0] + 8, c[1] - 8),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.4, (0, 255, 255), 1)
    return img


# --------------------------------------------------------------------------
# commands
# --------------------------------------------------------------------------
def cmd_preview(a):
    """Live view with a focus score. Maximise the focus number."""
    cap = open_camera(a.device, a.width, a.height)
    print("\nLive preview.")
    print("  Maximise FOCUS by adjusting camera distance / focus ring.")
    print("  Keep SAT% near 0 - clipped holes lose the edge detail we measure.")
    print("  q = quit   s = save snapshot\n")
    best = 0.0
    while True:
        ok, bgr = cap.read()
        if not ok:
            continue
        g = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
        focus = float(cv2.Laplacian(g, cv2.CV_64F).var())
        best = max(best, focus)
        sat = float((g >= 254).mean() * 100.0)
        txt = f"FOCUS {focus:7.1f} (best {best:7.1f})  SAT {sat:4.1f}%  mean {g.mean():5.1f}"
        cv2.putText(bgr, txt, (10, 28), cv2.FONT_HERSHEY_SIMPLEX, 0.6,
                    (0, 255, 0) if focus > best * 0.9 else (0, 200, 255), 2)
        cv2.imshow("preview - q to quit", bgr)
        k = cv2.waitKey(1) & 0xFF
        if k == ord('q'):
            break
        if k == ord('s'):
            OUT.mkdir(exist_ok=True)
            p = OUT / f"snap_{int(time.time())}.png"
            cv2.imwrite(str(p), bgr)
            print(f"saved {p}")
    cap.release()
    cv2.destroyAllWindows()


def cmd_calibrate(a):
    """Pick the ROI, then click two points a known distance apart."""
    cap = open_camera(a.device, a.width, a.height)
    gray, bgr = grab_gray(cap, a.frames)
    cap.release()
    OUT.mkdir(exist_ok=True)

    print("\nStep 1: drag a box around the TARGET AREA ONLY")
    print("  (exclude the edges of the backlight panel), then ENTER.\n")
    roi = cv2.selectROI("select target area - ENTER to accept", bgr,
                        showCrosshair=False)
    cv2.destroyAllWindows()
    if roi[2] < 10 or roi[3] < 10:
        sys.exit("ROI too small.")

    print("Step 2: click two points a KNOWN distance apart, then press any key.")
    t = TARGETS[a.target]
    print(f"  Tip: on a 10m air {a.target} card the BLACK AIMING MARK is")
    print(f"       {t['black_mm']} mm across and the outer scoring ring is "
          f"{t['outer_mm']} mm.")
    print("       Clicking the two edges of the black circle beats a ruler.\n")
    view = crop(bgr, roi).copy()
    pts = []

    MIN_SEP = 40  # px; two clicks closer than this are a stray double-click

    def on_click(ev, x, y, flags, param):
        if ev == cv2.EVENT_LBUTTONDOWN and len(pts) < 2:
            if pts and np.hypot(x - pts[0][0], y - pts[0][1]) < MIN_SEP:
                print(f"  ignored: that click is only "
                      f"{np.hypot(x - pts[0][0], y - pts[0][1]):.0f} px from the "
                      f"first one. Click the OPPOSITE edge of the circle.")
                return
            pts.append((x, y))
            cv2.drawMarker(view, (x, y), (0, 0, 255), cv2.MARKER_CROSS, 15, 2)
            if len(pts) == 2:
                cv2.line(view, pts[0], pts[1], (0, 255, 0), 1)
            cv2.imshow("click two points", view)

    cv2.imshow("click two points", view)
    cv2.setMouseCallback("click two points", on_click)
    while len(pts) < 2:
        if cv2.waitKey(20) & 0xFF == ord('q'):
            sys.exit("cancelled")
    cv2.waitKey(400)
    cv2.destroyAllWindows()

    dist_px = float(np.hypot(pts[1][0] - pts[0][0], pts[1][1] - pts[0][1]))
    known_mm = a.known_mm
    if known_mm is None:
        known_mm = float(input("distance between those two points in mm: "))
    mm_per_px = known_mm / dist_px

    # Sanity check: catch a mis-click before it poisons every later number.
    hole_px = PELLET_MM / mm_per_px
    roi_w_mm = roi[2] * mm_per_px
    problems = []
    if hole_px < 10:
        problems.append(f"a {PELLET_MM}mm pellet hole would be only "
                        f"{hole_px:.1f} px across (expect 25-60)")
    if roi_w_mm > 400:
        problems.append(f"your ROI would be {roi_w_mm:.0f} mm wide "
                        f"(expect roughly 60-250)")
    if roi_w_mm < 15:
        problems.append(f"your ROI would be only {roi_w_mm:.1f} mm wide")
    if problems:
        print("\n  REFUSING TO SAVE - this calibration looks wrong:")
        for pr in problems:
            print(f"    - {pr}")
        print(f"\n  You clicked 2 points {dist_px:.1f} px apart and called that "
              f"{known_mm} mm.")
        print("  Click the two OPPOSITE edges of the black circle, straight")
        print("  through its centre - they should be far apart on screen.")
        print("\n  Nothing was saved. Re-run calibrate.\n")
        sys.exit(1)

    save_calib({"roi": [int(v) for v in roi], "mm_per_px": mm_per_px,
                "known_mm": known_mm, "dist_px": dist_px,
                "width": a.width, "height": a.height, "device": a.device})
    print(f"\n  {dist_px:.1f} px = {known_mm} mm")
    print(f"  SCALE: {mm_per_px:.5f} mm/px   ({1/mm_per_px:.1f} px/mm)")
    print(f"  a {PELLET_MM}mm pellet hole spans ~{PELLET_MM/mm_per_px:.0f} px")


def n_frames_label(label):
    """Pull the frame count back out of a pass label like '16-frame avg'."""
    try:
        return int(label.split("-")[0])
    except ValueError:
        return 1


def cmd_jitter(a):
    """
    THE Phase 0 measurement.

    Nothing in the scene changes. We detect the same holes over and over and
    measure how far each centroid wanders. That standard deviation is the
    noise floor - the best this camera can ever do.
    """
    cal = load_calib()
    mm_px = cal["mm_per_px"]
    roi = cal["roi"]
    cap = open_camera(cal.get("device", a.device), cal["width"], cal["height"])
    OUT.mkdir(exist_ok=True)

    print(f"\nDo not touch anything. {a.rounds} rounds per pass.\n")
    results = {}
    for n_frames in (1, a.frames):
        label = f"{n_frames}-frame avg"
        rounds = []
        for r in range(a.rounds):
            gray, _ = grab_gray(cap, n_frames)
            dbg = (OUT / f"debug_{n_frames}f.png") if r == 0 else None
            holes, _, _ = detect_holes(crop(gray, roi), mm_px,
                                       max_holes=a.expect, debug_path=dbg)
            rounds.append(holes)
            print(f"  [{label}] round {r+1}/{a.rounds}: {len(holes)} holes", end="\r")
            time.sleep(0.15)
        print()

        counts = [len(h) for h in rounds]
        if counts[0] == 0:
            sys.exit("\nNo holes detected. Check backlight and ROI, "
                     "then re-run preview.")
        if len(set(counts)) > 1:
            print(f"  WARNING unstable hole count across rounds: {counts}")
        if a.expect is None and max(counts) > 8:
            print(f"\n  !! {max(counts)} 'holes' detected. If your target does not")
            print("     really have that many, the detector is picking up paper")
            print("     texture or glare and the jitter number below is MEANINGLESS.")
            print("     Re-run with --expect N (N = real number of holes),")
            print(f"     and check {OUT}/debug_{n_frames}f.png\n")

        ref = rounds[0]
        tol = 0.5 * PELLET_MM / mm_px
        # collect per-hole tracks
        tracks = [[] for _ in ref]
        for rr in rounds:
            m = match(ref, rr, tol)
            for i, c in enumerate(m):
                tracks[i].append(c)

        per_est = {}
        for bx, by, name in (("xb", "yb", "binary"), ("xw", "yw", "weighted")):
            devs = []
            for i, tr in enumerate(tracks):
                pts = [(c[bx], c[by]) for c in tr if c is not None]
                if len(pts) < 3:
                    continue
                arr = np.array(pts)
                sx, sy = arr[:, 0].std(ddof=1), arr[:, 1].std(ddof=1)
                devs.append(np.hypot(sx, sy))
            if devs:
                per_est[name] = (float(np.mean(devs)) * mm_px,
                                 float(np.max(devs)) * mm_px)
        results[label] = per_est

        img = annotate(crop(gray, roi), ref, mm_px)
        p = OUT / f"jitter_{n_frames}f.png"
        cv2.imwrite(str(p), img)

    cap.release()

    print("\n" + "=" * 62)
    print("NOISE FLOOR  (RMS centroid wander, scene static)")
    print("=" * 62)
    headline = None
    for label, per_est in results.items():
        for name, (mean_mm, max_mm) in per_est.items():
            print(f"  {label:>14}  {name:>8} centroid: "
                  f"mean {mean_mm:.4f} mm   worst {max_mm:.4f} mm")
            if n_frames_label(label) > 1 or headline is None:
                headline = mean_mm if headline is None else min(headline, mean_mm)
    print("=" * 62)
    if headline is not None:
        dec, integer = thresholds(a.target)
        t = TARGETS[a.target]
        print(f"\n  Best noise floor: {headline:.4f} mm")
        print(f"  Target: 10m air {a.target}  "
              f"(rings {t['ring_mm']:.0f}mm dia apart, 10-ring {t['ten_mm']}mm)")
        print(f"  Decimal scoring budget ~{dec:.2f} mm -> "
              f"{'PASS' if headline < dec else 'FAIL'}")
        print(f"  Integer rings budget   ~{integer:.2f} mm -> "
              f"{'PASS' if headline < integer else 'FAIL'}")
        if headline < dec:
            print(f"  margin: {dec / headline:.0f}x better than decimal needs")
        print("\n  (noise floor is the FLOOR - optics, mounting drift and")
        print("   overlapping holes all add error on top of this)")
    print(f"\n  annotated images in {OUT}/\n")


def cmd_detect(a):
    """Before/after new-hole detection. Also the overlapping-hole test."""
    cal = load_calib()
    mm_px, roi = cal["mm_per_px"], cal["roi"]
    cap = open_camera(cal.get("device", a.device), cal["width"], cal["height"])
    OUT.mkdir(exist_ok=True)

    input("\nBASELINE: leave the scene as-is and press ENTER...")
    before, _ = grab_gray(cap, a.frames)
    hb, _, _ = detect_holes(crop(before, roi), mm_px, max_holes=a.expect,
                            debug_path=OUT / "debug_before.png")
    print(f"  baseline: {len(hb)} holes")

    input("\nNow ADD A HOLE (try one overlapping an existing one), "
          "then press ENTER...")
    after, _ = grab_gray(cap, a.frames)
    ha, _, _ = detect_holes(crop(after, roi), mm_px,
                            max_holes=(a.expect + 1) if a.expect else None)
    print(f"  after: {len(ha)} holes")
    cap.release()

    # Difference image: what actually changed?
    diff = np.clip(crop(after, roi) - crop(before, roi), 0, None)
    hd, _, _ = detect_holes(diff, mm_px, min_mm=0.4)

    cv2.imwrite(str(OUT / "detect_before.png"), annotate(crop(before, roi), hb, mm_px))
    cv2.imwrite(str(OUT / "detect_after.png"), annotate(crop(after, roi), ha, mm_px))
    cv2.imwrite(str(OUT / "detect_diff.png"), annotate(diff, hd, mm_px))

    h, w = crop(before, roi).shape[:2]
    cx, cy = w / 2.0, h / 2.0
    # Measure the reference area from a REAL hole on the card when we have
    # one. The theoretical pellet area no longer matches, because the blur and
    # threshold inflate blobs by a consistent factor.
    if hb:
        expected_area = float(np.median([h["area_px"] for h in hb]))
        ref_src = f"measured from {len(hb)} baseline hole(s)"
    else:
        expected_area = np.pi * (PELLET_MM / 2.0 / mm_px) ** 2
        ref_src = "theoretical (no baseline hole to measure)"

    print("\n" + "=" * 62)
    print("NEW REGIONS IN THE DIFFERENCE IMAGE")
    print(f"reference hole area: {ref_src}")
    print("=" * 62)
    if not hd:
        print("  none found - was a hole actually added? is the rig steady?")
    for i, d in enumerate(hd):
        x_mm = (d["xw"] - cx) * mm_px
        y_mm = -(d["yw"] - cy) * mm_px  # image y is down; target y is up
        frac = d["area_px"] / expected_area
        conf = "clean" if frac > 0.75 else ("PARTIAL - likely overlap"
                                            if frac > 0.15 else "sliver - unreliable")
        print(f"  [{i}] x {x_mm:+7.2f} mm  y {y_mm:+7.2f} mm   "
              f"dia {d['diam_px']*mm_px:4.1f} mm   "
              f"area {frac*100:5.1f}% of a full hole   {conf}")
    print("=" * 62)
    print("\n  'x/y mm' is relative to the CENTRE OF THE ROI, not the target")
    print("  centre - Phase 1 adds a proper homography. For Phase 0 what")
    print("  matters is whether the new hole is found at all, and how the")
    print("  area fraction collapses when shots overlap.")
    print(f"\n  images in {OUT}/\n")


def cmd_snapshot(a):
    """Save raw / top-hat / mask / annotated images for diagnosis."""
    cal = load_calib()
    mm_px, roi = cal["mm_per_px"], cal["roi"]
    cap = open_camera(cal.get("device", a.device), cal["width"], cal["height"])
    gray, _ = grab_gray(cap, a.frames)
    cap.release()
    OUT.mkdir(exist_ok=True)

    g = crop(gray, roi)
    cv2.imwrite(str(OUT / "snap_raw.png"), np.clip(g, 0, 255).astype(np.uint8))
    holes, thr, _ = detect_holes(g, mm_px, max_holes=a.expect,
                                 debug_path=OUT / "snap_debug.png")
    cv2.imwrite(str(OUT / "snap_annotated.png"), annotate(g, holes, mm_px))

    print(f"\n  detected {len(holes)} hole(s), threshold {thr:.1f}")
    for i, h in enumerate(holes):
        flag = "  <-- TOUCHES ROI EDGE, position is wrong" if h["clipped"] else ""
        print(f"    [{i}] dia {h['diam_px']*mm_px:5.2f} mm  "
              f"circularity {h['circ']:.2f}  peak {h['peak']:.0f}  "
              f"saturated {h['sat']*100:.0f}%{flag}")
    print(f"\n  snap_raw.png        what the camera sees")
    print(f"  snap_debug.png      raw | top-hat | mask, side by side")
    print(f"  snap_annotated.png  what was detected")
    print(f"  in {OUT}/\n")


def cmd_drift(a):
    """
    Measure SLOW movement between runs - what `jitter` structurally cannot see.

    `jitter` references every round against round zero of the same run, so it
    only reports within-run scatter. Thermal expansion, mount settling, paper
    relaxing and focus hunting all act over minutes to hours. This logs an
    absolute position each time you run it, so the trend is visible.

    Run it, wait, run it again.
    """
    cal = load_calib()
    mm_px, roi = cal["mm_per_px"], cal["roi"]
    cap = open_camera(cal.get("device", a.device), cal["width"], cal["height"])
    gray, _ = grab_gray(cap, a.frames)
    cap.release()
    OUT.mkdir(exist_ok=True)

    holes, _, _ = detect_holes(crop(gray, roi), mm_px, max_holes=a.expect)
    if not holes:
        sys.exit("No hole detected - cannot log a drift point.")
    h = holes[0]

    log_path = HERE / "drift_log.json"
    log = json.loads(log_path.read_text()) if log_path.exists() else []
    entry = {"t": time.time(), "x_px": h["xw"], "y_px": h["yw"],
             "dia_mm": h["diam_px"] * mm_px, "circ": h["circ"],
             "peak": h["peak"], "mm_per_px": mm_px}
    log.append(entry)
    log_path.write_text(json.dumps(log, indent=2))

    # Keep a raw crop so later comparisons are like-for-like.
    cv2.imwrite(str(OUT / f"drift_{len(log):02d}.png"),
                np.clip(crop(gray, roi), 0, 255).astype(np.uint8))

    print(f"\n  logged point {len(log)}  ->  {log_path}")
    if len(log) == 1:
        print("  First point recorded. Wait a while, then run this again.\n")
        return

    first = log[0]
    print(f"\n{'pt':>3} {'elapsed':>9} {'dx mm':>8} {'dy mm':>8} "
          f"{'total mm':>9} {'dia mm':>7}")
    print("-" * 52)
    for i, e in enumerate(log, 1):
        dt = e["t"] - first["t"]
        dx = (e["x_px"] - first["x_px"]) * mm_px
        dy = (e["y_px"] - first["y_px"]) * mm_px
        hyp = float(np.hypot(dx, dy))
        el = f"{dt/60:.0f}m" if dt < 3600 else f"{dt/3600:.1f}h"
        print(f"{i:>3} {el:>9} {dx:>+8.3f} {dy:>+8.3f} {hyp:>9.3f} "
              f"{e['dia_mm']:>7.2f}")
    print("-" * 52)

    dec, _ = thresholds(a.target)
    worst = max(float(np.hypot((e["x_px"] - first["x_px"]) * mm_px,
                               (e["y_px"] - first["y_px"]) * mm_px))
                for e in log)
    print(f"\n  worst drift so far: {worst:.3f} mm "
          f"(decimal budget {dec:.3f} mm)")
    if worst > dec:
        print("\n  Drift exceeds the budget. This is EXPECTED and is why the")
        print("  real system must re-derive its geometry from the target's own")
        print("  printed rings in every frame, rather than trusting a fixed")
        print("  calibration. A static pixel->mm map cannot survive this.\n")
    else:
        print("  Within budget - mounting is stable at this timescale.\n")


def main():
    p = argparse.ArgumentParser(description="Phase 0 camera feasibility probe")
    sub = p.add_subparsers(dest="cmd", required=True)
    for name, fn, helptext in (
        ("preview", cmd_preview, "live view + focus score"),
        ("calibrate", cmd_calibrate, "set ROI and mm/pixel scale"),
        ("jitter", cmd_jitter, "measure the noise floor (the key number)"),
        ("detect", cmd_detect, "before/after new-hole detection"),
        ("snapshot", cmd_snapshot, "save raw/top-hat/mask images for diagnosis"),
        ("drift", cmd_drift, "log absolute position over time (run repeatedly)"),
    ):
        s = sub.add_parser(name, help=helptext)
        s.set_defaults(func=fn)
        s.add_argument("--device", type=int, default=0)
        s.add_argument("--width", type=int, default=1920)
        s.add_argument("--height", type=int, default=1080)
        s.add_argument("--frames", type=int, default=16,
                       help="frames averaged per capture")
        s.add_argument("--target", choices=sorted(TARGETS), default=DEFAULT_TARGET,
                       help="ISSF target type (sets the accuracy budget)")
        s.add_argument("--expect", type=int, default=None,
                       help="how many real holes are on the card; keeps only "
                            "the N strongest candidates")
        if name == "jitter":
            s.add_argument("--rounds", type=int, default=12)
        if name == "calibrate":
            s.add_argument("--known-mm", type=float, default=None)
    a = p.parse_args()
    a.func(a)


if __name__ == "__main__":
    main()
