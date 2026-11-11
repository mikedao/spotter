#!/usr/bin/env python3
"""
Locate the target in the image, from the target itself.

This replaces the static calib.json. The black aiming mark is a filled disc of
precisely known diameter (59.5mm for air pistol), so finding it in EVERY frame
gives us centre and scale every time. Camera drift, thermal creep and mount
settling then cancel out completely, because we only ever measure the hole's
position relative to the TARGET, never relative to the sensor.

Two models, in increasing order of correctness:

  1. ELLIPSE (affine). Fit an ellipse to the aiming mark and de-skew it back to
     a circle. Correct only for a camera square to the card. A circle seen in
     perspective still images as an exact ellipse, but the ellipse's CENTRE is
     not the image of the circle's centre, and the scale varies across the
     card. With the camera ~37 deg off to the side this put the outer rings
     ~9 mm out and the centre over a millimetre out.

  2. PERSPECTIVE (homography). Fit a full projective map to the aiming mark's
     edge AND every visible printed ring line together. Concentric circles of
     known radius pin down the true centre and the vanishing line, so the
     camera can sit off to the side, out of the line of fire.

Both are solved from the card itself in every frame; neither is a stored
calibration.
"""
import math
from dataclasses import dataclass
from typing import Optional

import cv2
import numpy as np

# Printed ring line width. ISSF ring diameters are taken to the OUTSIDE edge of
# the line, so the line's centre (what the fit locates) sits half a width
# inside the nominal radius. Not yet measured on a physical card - the per-ring
# mean residuals that fit_perspective reports will show it if this is wrong.
RING_LINE_MM = 0.2


def apply_h(Hm, x, y):
    """Apply a 3x3 homography to scalar or array coordinates."""
    x = np.asarray(x, dtype=np.float64)
    y = np.asarray(y, dtype=np.float64)
    w = Hm[2, 0] * x + Hm[2, 1] * y + Hm[2, 2]
    X = (Hm[0, 0] * x + Hm[0, 1] * y + Hm[0, 2]) / w
    Y = (Hm[1, 0] * x + Hm[1, 1] * y + Hm[1, 2]) / w
    if X.ndim == 0:
        return float(X), float(Y)
    return X, Y


@dataclass
class TargetFrame:
    cx: float            # image of the target centre, px
    cy: float
    semi_a: float        # aiming-mark ellipse semi-axis along `angle`, px
    semi_b: float        # semi-axis perpendicular, px
    angle_deg: float
    black_dia_mm: float
    area_px: float
    circularity: float
    # 3x3 UNDISTORTED image px -> target mm (y UP). None = ellipse model.
    H: Optional[np.ndarray] = None
    # Radial lens distortion, solved per frame alongside H:
    #   p_undist = c + (p - c) * (1 + k1 r^2 + k2 r^4),  r = |p - c| / norm
    # dist = (cx, cy, norm) in image px; None = no distortion model.
    k1: float = 0.0
    k2: float = 0.0
    dist: Optional[tuple] = None

    @property
    def perspective(self):
        return self.H is not None

    def undistort(self, px, py):
        if self.dist is None:
            return px, py
        dcx, dcy, dn = self.dist
        u = (np.asarray(px, np.float64) - dcx) / dn
        v = (np.asarray(py, np.float64) - dcy) / dn
        r2 = u * u + v * v
        s = 1.0 + self.k1 * r2 + self.k2 * r2 * r2
        return dcx + u * s * dn, dcy + v * s * dn

    def distort(self, ux, uy, iters=12):
        """Inverse of undistort, by fixed-point iteration."""
        if self.dist is None:
            return ux, uy
        dcx, dcy, dn = self.dist
        uu = (np.asarray(ux, np.float64) - dcx) / dn
        vu = (np.asarray(uy, np.float64) - dcy) / dn
        u, v = uu.copy(), vu.copy()
        for _ in range(iters):
            r2 = u * u + v * v
            s = 1.0 + self.k1 * r2 + self.k2 * r2 * r2
            u, v = uu / s, vu / s
        return dcx + u * dn, dcy + v * dn

    @property
    def axis_ratio(self):
        lo, hi = sorted((self.semi_a, self.semi_b))
        return lo / hi if hi else 0.0

    @property
    def mm_per_px(self):
        """Scale at the target centre. Under perspective it varies across the
        card, so use local_mm_per_px for anything position-specific."""
        if self.H is not None:
            return self.local_mm_per_px(self.cx, self.cy)
        r_mm = self.black_dia_mm / 2.0
        return (r_mm / self.semi_a + r_mm / self.semi_b) / 2.0

    def local_mm_per_px(self, px, py):
        """Geometric-mean scale at an image point (sqrt of the Jacobian)."""
        x0, y0 = self.to_mm(px, py)
        x1, y1 = self.to_mm(px + 1.0, py)
        x2, y2 = self.to_mm(px, py + 1.0)
        det = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
        return math.sqrt(abs(det))

    @property
    def tilt_deg(self):
        """Approximate off-axis angle implied by the aiming mark's shape."""
        return math.degrees(math.acos(min(1.0, max(0.0, self.axis_ratio))))

    @property
    def matrix(self):
        """3x3 image px -> target mm, for either model."""
        if self.H is not None:
            return self.H
        ox, oy = self._ellipse_to_mm(self.cx, self.cy)
        ax, ay = self._ellipse_to_mm(self.cx + 1.0, self.cy)
        bx, by = self._ellipse_to_mm(self.cx, self.cy + 1.0)
        L = np.array([[ax - ox, bx - ox], [ay - oy, by - oy]])
        t = np.array([ox, oy]) - L @ np.array([self.cx, self.cy])
        return np.array([[L[0, 0], L[0, 1], t[0]],
                         [L[1, 0], L[1, 1], t[1]],
                         [0.0, 0.0, 1.0]])

    def to_mm(self, px, py):
        """Image pixel -> target millimetres, origin at bull centre, y UP."""
        return apply_h(self.matrix, *self.undistort(px, py))

    def from_mm(self, x_mm, y_mm):
        """Inverse of to_mm: target millimetres -> image pixel."""
        ux, uy = apply_h(np.linalg.inv(self.matrix), x_mm, y_mm)
        x, y = self.distort(ux, uy)
        if np.ndim(x) == 0:
            return float(x), float(y)
        return x, y

    def _ellipse_to_mm(self, px, py):
        """Affine model: de-skew the aiming-mark ellipse to a circle."""
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

    def scaled(self, k):
        """
        The same frame for an image resized by factor k.

        cv2.resize maps pixel CENTRES, so new = (old + 0.5) * k - 0.5, not
        old * k. Ignoring the half pixel shifts everything by ~0.7 px when
        scaling a half-size solve back up.
        """
        o = 0.5 * k - 0.5                      # new = k * old + o
        S = np.array([[1.0 / k, 0, -o / k], [0, 1.0 / k, -o / k], [0, 0, 1.0]])
        return TargetFrame(cx=self.cx * k + o, cy=self.cy * k + o,
                           semi_a=self.semi_a * k, semi_b=self.semi_b * k,
                           angle_deg=self.angle_deg,
                           black_dia_mm=self.black_dia_mm,
                           area_px=self.area_px * k * k,
                           circularity=self.circularity,
                           H=None if self.H is None else self.H @ S,
                           k1=self.k1, k2=self.k2,
                           dist=None if self.dist is None else
                           (self.dist[0] * k + o, self.dist[1] * k + o,
                            self.dist[2] * k))

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
        # Judge roundness on the CONVEX HULL. Pellet holes on the rim of the
        # mark show as bright notches (very visible once the trap is
        # backlit through a diffuser) and dropped a real mark's circularity
        # to 0.43, losing two shots. The hull bridges notches; a mark merged
        # with a dark corner is still not round. refine_bull_ellipse rejects
        # rim points that fall on holes, so precision is unaffected.
        # ...but the hull of a frame-shaped dark background is a near-
        # rectangle (circularity pi/4 = 0.785), so also demand that the region
        # FILLS its hull: a notched disc does (~0.95), a frame or an L does not.
        raw_area = cv2.contourArea(cnt)
        cnt = cv2.convexHull(cnt)
        hull_area = cv2.contourArea(cnt)
        if hull_area <= 0 or raw_area / hull_area < 0.85:
            rejected.append((frac, raw_area / max(hull_area, 1.0)))
            continue
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


def ring_features(spec):
    """
    Printed circles usable for the fit: (radius_mm, kind, ring).

    kind is 'edge' for the aiming mark's rim (dark inside, light outside),
    'dark' for a black line on white paper, 'light' for a white line inside
    the black. Circles too small to sample (the rifle's 10 dot) are skipped.
    """
    from scoring import ring_radius_mm
    feats = []
    for ring in range(1, 11):
        R = ring_radius_mm(spec, ring)
        if ring == spec.black_ring:
            feats.append((R, "edge", ring))
        elif R - RING_LINE_MM / 2.0 < 2.0:
            continue
        else:
            feats.append((R - RING_LINE_MM / 2.0,
                          "dark" if ring < spec.black_ring else "light", ring))
    return feats


def _search_halfwidth(feats, spec):
    """Per-feature radial search window: 40% of the gap to the nearest other
    printed circle, so a search can never reach a neighbouring ring."""
    radii = sorted([f[0] for f in feats] + [spec.inner_ten_radius_mm, 0.0])
    out = []
    for R, _, _ in feats:
        gaps = [abs(R - o) for o in radii if abs(R - o) > 1e-6]
        out.append(0.4 * min(gaps))
    return out


def _extract_ring_points(img, w2i, feats, halfw, step_mm, n_rays=360):
    """
    Locate each printed circle along rays cast in TARGET space.

    Rays are radial in target millimetres and mapped into the image through
    the current model (w2i: target mm -> image px), so the search follows the
    perspective and lens distortion as the fit improves. Returns image points
    with the radius each one should have, and which feature it belongs to.
    """
    H, W = img.shape[:2]
    th = np.linspace(0, 2 * np.pi, n_rays, endpoint=False)
    ct, st = np.cos(th)[:, None], np.sin(th)[:, None]
    px, py, pR, pk = [], [], [], []
    for fi, ((R, kind, ring), hw) in enumerate(zip(feats, halfw)):
        r = R + np.arange(-hw, hw + step_mm / 2.0, step_mm)[None, :]
        ix, iy = w2i(r * ct, r * st)
        ok = np.all((ix >= 1) & (ix < W - 2) & (iy >= 1) & (iy < H - 2), axis=1)
        if not ok.any():
            continue
        prof = _sample_bilinear(img, np.clip(ix, 0, W - 2), np.clip(iy, 0, H - 2))
        m = prof.shape[1]
        med = np.median(prof, axis=1)

        if kind == "edge":
            v = np.diff(prof, axis=1)              # dark inside -> light out
            off = 0.5
            k = np.argmax(v, axis=1)
            strength = (np.median(prof[:, -m // 3:], axis=1) -
                        np.median(prof[:, : m // 3], axis=1))
            ok &= strength > 40
        else:
            v = -prof if kind == "dark" else prof
            off = 0.0
            k = np.argmax(v, axis=1)
            peak = v[np.arange(len(k)), k]
            strength = peak + (med if kind == "dark" else -med)
            # a dark line must sit on paper, a light line on the black
            ok &= (med > 90) if kind == "dark" else (med < 90)
            ok &= strength > 15

        idx = np.arange(len(k))
        ok &= (k > 0) & (k < v.shape[1] - 1)
        kk = np.clip(k, 1, v.shape[1] - 2)
        vm1, v0, vp1 = v[idx, kk - 1], v[idx, kk], v[idx, kk + 1]
        den = vm1 - 2 * v0 + vp1
        delta = np.where(np.abs(den) > 1e-9, 0.5 * (vm1 - vp1) / den, 0.0)
        delta = np.clip(delta, -1.0, 1.0)
        r_hat = r[0, 0] + (kk + off + delta) * step_mm
        x, y = w2i(r_hat * ct[:, 0], r_hat * st[:, 0])
        px.append(x[ok]); py.append(y[ok])
        pR.append(np.full(ok.sum(), R)); pk.append(np.full(ok.sum(), fi))
    if not px:
        return (np.empty(0),) * 4
    return (np.concatenate(px), np.concatenate(py),
            np.concatenate(pR), np.concatenate(pk).astype(int))


# Model parameters: a, b, d, tx, ty, l1, l2, k1, k2
#   undistort:  p_u = c + (p - c) (1 + k1 r^2 + k2 r^4)
#   normalise:  q = (p_u - c0) / s0
#   project:    target = A . P . q,  A upper-triangular affine,
#               P = [[1,0,0],[0,1,0],[l1,l2,1]]
def _model_resid(theta, x, y, R, ctx):
    a, b, d, tx, ty, l1, l2, k1, k2 = theta
    dcx, dcy, dn, cx0, cy0, s0 = ctx
    u, v = (x - dcx) / dn, (y - dcy) / dn
    r2 = u * u + v * v
    s = 1.0 + k1 * r2 + k2 * r2 * r2
    qx = (dcx + u * s * dn - cx0) / s0
    qy = (dcy + v * s * dn - cy0) / s0
    w = l1 * qx + l2 * qy + 1.0
    X = (a * qx + b * qy) / w + tx
    Y = d * qy / w + ty
    return np.hypot(X, Y) - R


def _lm(theta, free, x, y, R, ctx, iters=60):
    """Levenberg-Marquardt on radial residuals (mm), numeric Jacobian, over
    the parameters flagged in `free`."""
    theta = theta.astype(np.float64).copy()
    fi = np.where(free)[0]
    lam = 1e-3
    r = _model_resid(theta, x, y, R, ctx)
    cost = float(r @ r)
    for _ in range(iters):
        J = np.empty((len(r), len(fi)))
        for c, j in enumerate(fi):
            h = 1e-7 * max(1.0, abs(theta[j]))
            tp = theta.copy(); tp[j] += h
            tm = theta.copy(); tm[j] -= h
            J[:, c] = (_model_resid(tp, x, y, R, ctx) -
                       _model_resid(tm, x, y, R, ctx)) / (2 * h)
        A = J.T @ J
        g = J.T @ r
        improved, rel = False, 0.0
        for _ in range(12):
            try:
                step = np.linalg.solve(A + lam * np.diag(np.diag(A) + 1e-12), -g)
            except np.linalg.LinAlgError:
                lam *= 10
                continue
            tn = theta.copy()
            tn[fi] += step
            rn = _model_resid(tn, x, y, R, ctx)
            cn = float(rn @ rn)
            if np.isfinite(cn) and cn < cost:
                rel = (cost - cn) / max(cost, 1e-12)
                theta, r, cost = tn, rn, cn
                lam = max(lam / 3.0, 1e-9)
                improved = True
                break
            lam *= 4.0
        if not improved or rel < 1e-10:
            break
    return theta


def fit_perspective(gray_flat, tf, spec, n_rays=360, max_rms_mm=0.35,
                    distortion=True):
    """
    Fit perspective + lens distortion to the aiming mark and the printed rings.

    A circle in perspective images as an exact ellipse, so the aiming mark
    alone cannot reveal perspective. Several CONCENTRIC circles of known radius
    can: together they fix the true centre (not the ellipse centre) and how
    scale changes across the card. That is what lets the camera sit off to
    the side, out of the line of fire.

    A wide-angle webcam also bends straight lines. On a real Kiyo frame a
    homography alone left a systematic ring-by-ring curve of -0.4 to +0.5 mm;
    two radial terms (centred on the image centre) took every ring's mean
    residual to ~0. Distortion is solved here, per frame, like everything else.

    Rotation about the card's normal leaves circles unchanged, so it cannot be
    fitted; it is fixed afterwards so that image-up is target-up.

    Rings are added outward from the aiming mark in stages, re-searching each
    time with the latest model, because the starting ellipse model can be
    several mm out at the outer rings. Distortion is only freed once every
    ring is in, when there is enough radial spread to pin it down.

    Returns (TargetFrame, info). On failure returns the input tf unchanged with
    info["perspective"] False and a reason.
    """
    img = cv2.GaussianBlur(gray_flat.astype(np.float32), (0, 0), 1.0)
    Himg, Wimg = img.shape[:2]
    feats_all = ring_features(spec)
    halfw_all = _search_halfwidth(feats_all, spec)
    R_bull = spec.black_dia_mm / 2.0

    dist = (Wimg / 2.0, Himg / 2.0, Wimg / 2.0)
    s0 = 0.5 * (tf.semi_a + tf.semi_b)
    cx0, cy0 = tf.cx, tf.cy
    ctx = dist + (cx0, cy0, s0)
    N = np.array([[1 / s0, 0, -cx0 / s0], [0, 1 / s0, -cy0 / s0], [0, 0, 1.0]])

    # initialise from the ellipse model: target = L (p - c0); QR drops rotation
    _, Rq = np.linalg.qr(tf.matrix[:2, :2] * s0)
    theta = np.array([Rq[0, 0], Rq[0, 1], Rq[1, 1], 0, 0, 0, 0, 0, 0], float)

    def frame_of(th):
        a, b, d, tx, ty, l1, l2, k1, k2 = th
        A = np.array([[a, b, tx], [0, d, ty], [0, 0, 1.0]])
        P = np.array([[1, 0, 0], [0, 1, 0], [l1, l2, 1.0]])
        return TargetFrame(cx=tf.cx, cy=tf.cy, semi_a=tf.semi_a,
                           semi_b=tf.semi_b, angle_deg=tf.angle_deg,
                           black_dia_mm=tf.black_dia_mm, area_px=tf.area_px,
                           circularity=tf.circularity, H=A @ P @ N,
                           k1=float(k1), k2=float(k2), dist=dist)

    step_mm = 0.25 * tf.mm_per_px
    dist_mm = np.array([abs(f[0] - R_bull) for f in feats_all])
    reach = 1.25 * spec.step_mm
    stages = []
    while True:
        sel = np.where(dist_mm <= reach)[0]
        stages.append((sel, False))
        if len(sel) == len(feats_all):
            break
        reach += spec.step_mm
    stages += [(stages[-1][0], distortion)] * 3     # polish with everything

    for sel, free_dist in stages:
        feats = [feats_all[i] for i in sel]
        halfw = [halfw_all[i] for i in sel]
        x, y, R, k = _extract_ring_points(img, frame_of(theta).from_mm, feats,
                                          halfw, step_mm, n_rays)
        if len(x) < 60:
            return tf, {"perspective": False,
                        "reason": f"only {len(x)} ring points found"}
        free = np.array([1, 1, 1, 1, 1, 1, 1, free_dist, free_dist], bool)
        keep = np.ones(len(x), bool)
        for _ in range(4):                     # robust: trim and refit
            theta = _lm(theta, free, x[keep], y[keep], R[keep], ctx)
            res = _model_resid(theta, x, y, R, ctx)
            sd = 1.4826 * np.median(np.abs(res[keep]))
            new_keep = np.abs(res) < max(3.0 * sd, 0.03)
            if (new_keep == keep).all():
                break
            keep = new_keep

    res = _model_resid(theta, x, y, R, ctx)
    rms = float(np.sqrt(np.mean(res[keep] ** 2)))
    fit = frame_of(theta)

    # fix the unobservable rotation: image-up through the centre is target +y
    Hfit = fit.H
    c = np.linalg.inv(Hfit) @ np.array([0.0, 0.0, 1.0])
    cxu, cyu = c[0] / c[2], c[1] / c[2]          # undistorted centre
    ux, uy = apply_h(Hfit, cxu, cyu - 0.2 * s0)
    phi = math.pi / 2 - math.atan2(uy, ux)
    G = np.array([[math.cos(phi), -math.sin(phi), 0],
                  [math.sin(phi), math.cos(phi), 0], [0, 0, 1.0]])
    rx, _ = apply_h(G @ Hfit, cxu + 0.2 * s0, cyu)
    if rx < 0:                                   # keep image-right = target +x
        G = np.diag([-1.0, 1.0, 1.0]) @ G
    fit.H = G @ Hfit
    fit.cx, fit.cy = fit.from_mm(0.0, 0.0)

    per_ring = {}
    for j, fi in enumerate(sel):
        m = keep & (k == j)
        if m.sum():
            per_ring[feats_all[fi][2]] = (int(m.sum()), float(res[m].mean()),
                                          float(np.sqrt(np.mean(res[m] ** 2))))

    # Card flatness: mean residual per ring per 30-deg sector. A bowed card
    # leaves smooth patches shared by neighbouring rings that a per-ring mean
    # averages away; off-axis, a bump of height h shifts by ~h*tan(angle).
    X, Y = fit.to_mm(x, y)
    ang = np.degrees(np.arctan2(Y, X)) % 360.0
    sector = (ang // 30).astype(int)
    worst, worst_at = 0.0, None
    for j, fi in enumerate(sel):
        for sct in range(12):
            m = keep & (k == j) & (sector == sct)
            if m.sum() >= 6:
                v = float(res[m].mean())
                if abs(v) > abs(worst):
                    worst, worst_at = v, (feats_all[fi][2], sct * 30 + 15)

    sl = [fit.local_mm_per_px(*fit.from_mm(R_bull * math.cos(a),
                                           R_bull * math.sin(a)))
          for a in np.linspace(0, 2 * np.pi, 8, endpoint=False)]
    info = {"perspective": True, "points": int(keep.sum()),
            "rejected": int((~keep).sum()), "rms_mm": rms, "rings": per_ring,
            "k1": fit.k1, "k2": fit.k2,
            "flat_worst_mm": worst, "flat_worst_at": worst_at,
            # how much scale changes across the aiming mark: the honest
            # "how oblique is the camera" number
            "scale_spread_pct": (max(sl) / min(sl) - 1.0) * 100.0,
            "centre_shift_px": math.hypot(fit.cx - tf.cx, fit.cy - tf.cy)}

    if not np.isfinite(rms) or rms > max_rms_mm or len(per_ring) < 3:
        info.update(perspective=False,
                    reason=f"ring fit RMS {rms:.3f} mm over {len(per_ring)} "
                           f"rings - keeping the ellipse model")
        return tf, info
    return fit, info


def offscreen_sides(tf, r_mm, shape):
    """Which image edges a target-space circle of radius r_mm runs past."""
    H, W = shape[:2]
    a = np.linspace(0, 2 * np.pi, 180, endpoint=False)
    x, y = tf.from_mm(r_mm * np.cos(a), r_mm * np.sin(a))
    return [n for n, v in (("left", x.min() < 0), ("top", y.min() < 0),
                           ("right", x.max() > W - 1),
                           ("bottom", y.max() > H - 1)) if v]


def register(src_img, tf_src, tf_dst, shape):
    """
    Resample src_img into the geometry of the dst frame, through the target.

    Both frames describe the SAME physical card, so every dst pixel maps
    dst-px -> target mm -> src-px. Doing it densely (cv2.remap) handles
    perspective and lens distortion exactly, which a 3x3 warp cannot. The
    difference of dst and the result is then meaningful even if the camera
    moved between captures.
    """
    H, W = shape[:2]
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float64)
    mx, my = tf_dst.to_mm(xx, yy)
    sx, sy = tf_src.from_mm(mx, my)
    return cv2.remap(src_img.astype(np.float32), sx.astype(np.float32),
                     sy.astype(np.float32), cv2.INTER_LINEAR,
                     borderMode=cv2.BORDER_REPLICATE)


def new_light(after, before_reg, radius_px=2):
    """
    Where the after frame got brighter than the (registered) before frame,
    counting a pixel only if it beats EVERY before pixel within radius_px.

    A plain after - before difference lights up every printed edge: frames
    differ slightly in sharpness and scale (autofocus cannot be locked on
    macOS; scale moved up to 0.6% between shots) and a sub-pixel mismatch on
    a sharp line is a bright line in the difference. On real shots that gave
    up to 114 regions, and a hole on the aiming-mark edge merged with the edge
    residue into one tall blob that the filters rejected - the shot was lost.
    A max-filter on the before frame absorbs any edge that moved by up to
    radius_px, while a new hole (bright where the before was dark over its
    whole area) survives, minus a thin rim.
    """
    k = 2 * radius_px + 1
    se = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k, k))
    bmax = cv2.dilate(np.asarray(before_reg, np.float32), se)
    return np.clip(np.asarray(after, np.float32) - bmax, 0, None)


def frame_shift_mm(tf_from, tf_to):
    """How far the camera moved between two frames, in target mm."""
    x, y = tf_to.to_mm(tf_from.cx, tf_from.cy)
    scale_pct = (tf_to.mm_per_px / tf_from.mm_per_px - 1.0) * 100.0
    return math.hypot(x, y), scale_pct

def draw_rings(img_bgr, tf, spec):
    """Overlay the derived ring geometry so you can eyeball the fit."""
    from scoring import ring_radius_mm
    a = np.linspace(0, 2 * np.pi, 360, endpoint=False)
    for ring in range(10, 0, -1):
        rr = ring_radius_mm(spec, ring)
        x, y = tf.from_mm(rr * np.cos(a), rr * np.sin(a))
        pts = np.round(np.stack([x, y], 1) * 16).astype(np.int32)
        cv2.polylines(img_bgr, [pts], True, (0, 200, 255), 1, cv2.LINE_AA,
                      shift=4)
    cv2.drawMarker(img_bgr, (int(tf.cx), int(tf.cy)), (0, 0, 255),
                   cv2.MARKER_CROSS, 25, 2)
    return img_bgr
