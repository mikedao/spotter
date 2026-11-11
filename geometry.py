#!/usr/bin/env python3
"""
Locate the target in the image, from the target itself.

This replaces the static calib.json. The black aiming mark is a filled disc of
precisely known diameter (59.5mm for air pistol), so finding it in EVERY frame
gives us centre and scale every time. Camera drift, thermal creep and mount
settling then cancel out completely, because we only ever measure the hole's
position relative to the TARGET, never relative to the sensor.

Fitting an ELLIPSE rather than a circle also buys first-order tilt correction:
a circle viewed off-axis projects to an ellipse, and de-skewing that ellipse
back to a circle undoes the foreshortening.
"""
import math
from dataclasses import dataclass

import cv2
import numpy as np


@dataclass
class TargetFrame:
    cx: float            # bull centre, px
    cy: float
    semi_a: float        # semi-axis along `angle`, px
    semi_b: float        # semi-axis perpendicular, px
    angle_deg: float
    black_dia_mm: float
    area_px: float
    circularity: float

    @property
    def axis_ratio(self):
        lo, hi = sorted((self.semi_a, self.semi_b))
        return lo / hi if hi else 0.0

    @property
    def mm_per_px(self):
        """Mean scale - for reporting only; to_mm uses both axes."""
        r_mm = self.black_dia_mm / 2.0
        return (r_mm / self.semi_a + r_mm / self.semi_b) / 2.0

    @property
    def tilt_deg(self):
        """Approximate off-axis angle implied by the foreshortening."""
        return math.degrees(math.acos(min(1.0, max(0.0, self.axis_ratio))))

    def to_mm(self, px, py):
        """Image pixel -> target millimetres, origin at bull centre, y UP."""
        r_mm = self.black_dia_mm / 2.0
        th = math.radians(self.angle_deg)
        c, s = math.cos(th), math.sin(th)

        vx, vy = px - self.cx, py - self.cy
        # into ellipse-aligned frame
        ux = vx * c + vy * s
        uy = -vx * s + vy * c
        # de-skew to a true circle, in mm
        ax = ux * (r_mm / self.semi_a)
        by = uy * (r_mm / self.semi_b)
        # back to image-aligned orientation
        x_mm = ax * c - by * s
        y_mm = ax * s + by * c
        return x_mm, -y_mm          # image y is down, target y is up

    def from_mm(self, x_mm, y_mm):
        """Inverse of to_mm: target millimetres -> image pixel."""
        r_mm = self.black_dia_mm / 2.0
        th = math.radians(self.angle_deg)
        c, s = math.cos(th), math.sin(th)

        x, y = x_mm, -y_mm
        a = x * c + y * s
        b = -x * s + y * c
        ux = a * (self.semi_a / r_mm)
        uy = b * (self.semi_b / r_mm)
        vx = ux * c - uy * s
        vy = ux * s + uy * c
        return vx + self.cx, vy + self.cy

    def radius_mm(self, px, py):
        x, y = self.to_mm(px, py)
        return math.hypot(x, y)


def flatten_illumination(g8, order2=True, target_level=160.0, iters=3):
    """
    Remove smooth lighting gradients before thresholding.

    A single global threshold cannot cope with uneven lighting: if one corner
    of the paper is dimmer than the ink elsewhere, Otsu merges them. We fit a
    smooth 2nd-order surface to the PAPER pixels only (iteratively rejecting
    dark ink as outliers) and divide it out, which flattens the field while
    leaving the ink/paper contrast intact.

    Returns (flattened uint8, background float array).
    """
    H, W = g8.shape[:2]
    yy, xx = np.mgrid[0:H, 0:W]
    xn = xx / W - 0.5
    yn = yy / H - 0.5
    terms = [np.ones_like(xn), xn, yn]
    if order2:
        terms += [xn * xn, xn * yn, yn * yn]
    A = np.stack([t.ravel() for t in terms], axis=1)
    z = g8.astype(np.float64).ravel()

    # Fit on a subsample for speed; evaluate on everything.
    step = max(1, (H * W) // 60000)
    As, zs = A[::step], z[::step]

    keep = zs > np.median(zs)          # start from the brighter half = paper
    coef = None
    for _ in range(iters):
        if keep.sum() < len(terms) * 10:
            break
        coef, *_ = np.linalg.lstsq(As[keep], zs[keep], rcond=None)
        resid = zs - As @ coef
        sd = resid[keep].std() or 1.0
        keep = resid > -1.0 * sd       # reject dark ink, keep paper
    if coef is None:
        return g8, np.full((H, W), float(g8.mean()))

    bg = np.clip((A @ coef).reshape(H, W), 1.0, None)
    out = np.clip(g8.astype(np.float64) / bg * target_level, 0, 255)
    return out.astype(np.uint8), bg


def find_target_frame(gray, black_dia_mm=59.5, min_area_frac=0.005,
                      max_area_frac=0.70, min_circularity=0.70,
                      debug_path=None):
    """
    Find the black aiming mark and fit an ellipse to it.

    Returns (TargetFrame | None, diagnostics dict).
    """
    g8 = np.clip(gray, 0, 255).astype(np.uint8)
    H, W = g8.shape[:2]
    g8, _bg = flatten_illumination(g8)
    g8 = cv2.GaussianBlur(g8, (0, 0), 2.0)

    # The bull is the DARK region. Otsu splits ink from paper - which only
    # works because the field has been flattened above.
    thr, mask = cv2.threshold(g8, 0, 255,
                              cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)

    # Thin ring lines are also dark. An opening removes anything narrow while
    # leaving a disc hundreds of px across untouched.
    k = max(9, int(0.015 * min(H, W))) | 1
    mask = cv2.morphologyEx(
        mask, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k, k)))

    n, labels, stats, _ = cv2.connectedComponentsWithStats(mask, connectivity=8)
    img_area = float(H * W)
    best, best_info = None, None
    rejected = []

    for i in range(1, n):
        area = float(stats[i, cv2.CC_STAT_AREA])
        frac = area / img_area
        if not (min_area_frac <= frac <= max_area_frac):
            continue
        comp = (labels == i).astype(np.uint8)
        # RETR_EXTERNAL ignores interior holes, so a pellet hole punched
        # through the bull does not disturb the outline.
        cnts, _ = cv2.findContours(comp, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
        if not cnts:
            continue
        cnt = max(cnts, key=cv2.contourArea)
        if len(cnt) < 5:                      # fitEllipse needs >= 5 points
            continue
        per = cv2.arcLength(cnt, True)
        if per <= 0:
            continue
        circ = 4.0 * math.pi * cv2.contourArea(cnt) / (per * per)
        if circ < min_circularity:
            rejected.append((frac, circ))
            continue
        if best is None or area > best_info[0]:
            best, best_info = cnt, (area, circ)

    diag = {"threshold": float(thr), "components": int(n - 1),
            "rejected_round": rejected, "open_kernel": k}

    if best is None:
        diag["reason"] = "no sufficiently large, round dark region found"
        if debug_path is not None:
            cv2.imwrite(str(debug_path), np.hstack([g8, mask]))
        return None, diag

    (ex, ey), (d1, d2), ang = cv2.fitEllipse(best)
    tf = TargetFrame(cx=float(ex), cy=float(ey),
                     semi_a=float(d1) / 2.0, semi_b=float(d2) / 2.0,
                     angle_deg=float(ang), black_dia_mm=black_dia_mm,
                     area_px=best_info[0], circularity=best_info[1])

    if debug_path is not None:
        vis = cv2.cvtColor(g8, cv2.COLOR_GRAY2BGR)
        cv2.ellipse(vis, ((ex, ey), (d1, d2), ang), (0, 255, 0), 2)
        cv2.drawMarker(vis, (int(ex), int(ey)), (0, 0, 255),
                       cv2.MARKER_CROSS, 25, 2)
        cv2.imwrite(str(debug_path), np.hstack([vis, cv2.cvtColor(mask,
                                                cv2.COLOR_GRAY2BGR)]))
    return tf, diag



def _ellipse_r(theta, a, b, phi):
    """Radius of an ellipse (semi-axes a,b rotated by phi) at image angle theta."""
    t = theta - phi
    ct, st = np.cos(t), np.sin(t)
    return (a * b) / np.sqrt((b * ct) ** 2 + (a * st) ** 2 + 1e-12)


def _sample_bilinear(img, xs, ys):
    H, W = img.shape[:2]
    x0 = np.clip(np.floor(xs).astype(np.int32), 0, W - 2)
    y0 = np.clip(np.floor(ys).astype(np.int32), 0, H - 2)
    fx, fy = xs - x0, ys - y0
    v = (img[y0, x0] * (1 - fx) * (1 - fy) + img[y0, x0 + 1] * fx * (1 - fy) +
         img[y0 + 1, x0] * (1 - fx) * fy + img[y0 + 1, x0 + 1] * fx * fy)
    return v


def refine_bull_ellipse(gray_flat, tf, n_rays=360, span_in=0.15, span_out=0.15,
                        step=0.3, reject_sigma=2.0, iters=3, max_scale_change=0.25):
    """
    Re-fit the aiming mark by locating its EDGE directly.

    The thresholded blob outline is fragile: a merged dark corner or vignette
    distorts it, and the boundary is quantised to whole pixels. Instead we cast
    rays outward from the centre, find the dark->light transition on each by
    its peak intensity gradient (sub-pixel, via parabolic interpolation), then
    fit an ellipse to those edge points while rejecting outliers.

    Rays that hit a merged dark region, a pellet hole on the rim, or a printed
    numeral simply become outliers and drop out.
    """
    a, b, phi = tf.semi_a, tf.semi_b, np.radians(tf.angle_deg)
    cx, cy = tf.cx, tf.cy
    img = gray_flat.astype(np.float32)

    for _ in range(iters):
        thetas = np.linspace(0, 2 * np.pi, n_rays, endpoint=False)
        r_exp = _ellipse_r(thetas, a, b, phi)
        r_lo, r_hi = r_exp * (1 - span_in), r_exp * (1 + span_out)
        m = int(np.ceil((r_hi - r_lo).max() / step)) + 1
        frac = np.linspace(0.0, 1.0, m)[None, :]
        rr = r_lo[:, None] + (r_hi - r_lo)[:, None] * frac

        xs = cx + rr * np.cos(thetas)[:, None]
        ys = cy + rr * np.sin(thetas)[:, None]
        prof = _sample_bilinear(img, xs, ys)

        grad = np.diff(prof, axis=1)          # dark inside -> bright outside
        k = np.argmax(grad, axis=1)
        ok = (k > 0) & (k < grad.shape[1] - 1)

        # parabolic sub-pixel peak of the gradient
        idx = np.arange(len(k))
        gm1 = grad[idx, np.clip(k - 1, 0, None)]
        g0 = grad[idx, k]
        gp1 = grad[idx, np.clip(k + 1, 0, grad.shape[1] - 1)]
        denom = (gm1 - 2 * g0 + gp1)
        delta = np.where(np.abs(denom) > 1e-6, 0.5 * (gm1 - gp1) / denom, 0.0)
        delta = np.clip(delta, -1.0, 1.0)
        r_edge = rr[idx, k] + delta * (rr[idx, 1] - rr[idx, 0])

        # keep only confident edges
        ok &= g0 > max(np.median(g0) * 0.6, 2.0)
        if ok.sum() < 20:
            return tf, {"refined": False, "reason": "too few edge points"}

        th_ok, r_ok = thetas[ok], r_edge[ok]
        for _ in range(3):   # robust: drop points far from the current fit
            pts = np.stack([cx + r_ok * np.cos(th_ok),
                            cy + r_ok * np.sin(th_ok)], axis=1).astype(np.float32)
            if len(pts) < 10:
                break
            (ex, ey), (d1, d2), ang = cv2.fitEllipse(pts.reshape(-1, 1, 2))
            a2, b2, phi2 = d1 / 2.0, d2 / 2.0, np.radians(ang)
            th_rel = np.arctan2(pts[:, 1] - ey, pts[:, 0] - ex)
            pred = _ellipse_r(th_rel, a2, b2, phi2)
            actual = np.hypot(pts[:, 0] - ex, pts[:, 1] - ey)
            res = actual - pred
            sd = np.median(np.abs(res - np.median(res))) * 1.4826 or 1.0
            keep = np.abs(res - np.median(res)) < reject_sigma * sd
            if keep.all():
                break
            th_ok, r_ok = th_ok[keep], r_ok[keep]
        cx, cy, a, b, phi = ex, ey, a2, b2, phi2

    rms = float(np.sqrt(np.mean(res[keep] ** 2))) if len(res) else float("nan")
    scale_change = abs((a + b) / (tf.semi_a + tf.semi_b) - 1.0)
    if scale_change > max_scale_change or not np.isfinite(rms):
        return tf, {"refined": False,
                    "reason": f"refinement moved scale by {scale_change*100:.0f}% "
                              f"(rms {rms:.1f}px) - keeping threshold fit"}
    out = TargetFrame(cx=float(cx), cy=float(cy), semi_a=float(a), semi_b=float(b),
                      angle_deg=float(np.degrees(phi)),
                      black_dia_mm=tf.black_dia_mm, area_px=tf.area_px,
                      circularity=tf.circularity)
    return out, {"refined": True, "edge_points": int(keep.sum()),
                 "edge_rms_px": rms}


def align_matrix(tf_from, tf_to, shape):
    """
    2x3 affine mapping TO-image coordinates back into FROM-image coordinates.

    Both frames describe the SAME physical circle, so composing
    to-pixels -> mm -> from-pixels registers the two images through the target
    itself. Feed this to cv2.warpAffine(from_image, M, size) and the result is
    the "from" image resampled into the "to" image's geometry, so a difference
    is then meaningful even if the camera moved between captures.
    """
    H, W = shape[:2]
    src = np.float32([[0, 0], [W - 1, 0], [0, H - 1]])
    dst = np.float32([tf_from.from_mm(*tf_to.to_mm(x, y)) for x, y in src])
    return cv2.getAffineTransform(src, dst)


def frame_shift_mm(tf_from, tf_to):
    """How far the camera moved between two frames, in target mm."""
    x, y = tf_to.to_mm(tf_from.cx, tf_from.cy)
    scale_pct = (tf_to.mm_per_px / tf_from.mm_per_px - 1.0) * 100.0
    return math.hypot(x, y), scale_pct

def draw_rings(img_bgr, tf, spec):
    """Overlay the derived ring geometry so you can eyeball the fit."""
    from scoring import ring_radius_mm
    r_mm = tf.black_dia_mm / 2.0
    for ring in range(10, 0, -1):
        rr = ring_radius_mm(spec, ring)
        d1 = 2.0 * rr * (tf.semi_a / r_mm)
        d2 = 2.0 * rr * (tf.semi_b / r_mm)
        cv2.ellipse(img_bgr, ((tf.cx, tf.cy), (d1, d2), tf.angle_deg),
                    (0, 200, 255), 1)
    cv2.drawMarker(img_bgr, (int(tf.cx), int(tf.cy)), (0, 0, 255),
                   cv2.MARKER_CROSS, 25, 2)
    return img_bgr
