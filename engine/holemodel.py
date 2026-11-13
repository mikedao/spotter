#!/usr/bin/env python3
"""
The learned hole locator: where is the pellet's centre in a shot's close-ups?

Trained on the shooter's review calls (engine/ml/train.py) and run here with
OpenCV's own dnn module from an ONNX file, so the engine needs nothing new. It
answers WHERE only; scoring.py still turns a position into a ring and decimal.

Everything both sides must agree on lives in this file, so training and the live
engine can never see different pixels or read the output differently:

  INPUT   the before and after close-ups (report.closeup: top-down, 20 px/mm,
          480 px, y UP, centred on the rules' position), as their JPEGs (what the
          web app stores and the trainer reads). A CROP_MM square around the
          centre is sampled at IN_PPM px/mm -> channels before, after, after-before.
  OUTPUT  logits on a GRID x GRID heatmap over that square (one cell = CELL_MM).
          softmax = the probability the pellet's centre is in each cell; the
          position is its mean, the uncertainty its spread, and P(ring) is read
          from the probabilities themselves (a hole torn two ways keeps both).

Positions in the model's own frame are mm OFFSETS from the crop centre, x right,
y UP, as everywhere in Spotter.
"""
import json
import math
from pathlib import Path

import cv2
import numpy as np

import scoring

CLOSEUP_PPM = 20.0      # report.closeup's px_per_mm
CLOSEUP_PX = 480
CROP_MM = 20.0          # the square the model sees (+-10 mm: wrong-spot misses reach 8)
IN_PPM = 8.0            # model input resolution
IN_PX = int(CROP_MM * IN_PPM)      # 160
STRIDE = 4              # heatmap cell = STRIDE input px
GRID = IN_PX // STRIDE             # 40
CELL_MM = CROP_MM / GRID           # 0.5 mm
JPEG_QUALITY = 90       # report.jpeg's: live close-ups go through the same JPEG

MODEL_DIR = Path(__file__).resolve().parent / "out" / "ml" / "model"


def cell_offsets():
    """(GRID, GRID, 2) mm offset of each heatmap cell's centre from the crop centre."""
    c = (np.arange(GRID) + 0.5) * CELL_MM - CROP_MM / 2
    xs = np.broadcast_to(c[None, :], (GRID, GRID))
    ys = np.broadcast_to(-c[:, None], (GRID, GRID))      # row 0 = top = +y
    return np.stack([xs, ys], -1)


def decode_jpeg(data):
    return cv2.imdecode(np.frombuffer(data, np.uint8), cv2.IMREAD_GRAYSCALE)


def sample(closeup, A=None, t=(0.0, 0.0)):
    """
    The model's view of one close-up: IN_PX square at IN_PPM. A (2x2, a rotation
    and/or flip) and t (mm) are training's augmentation - an output offset q
    shows the close-up at offset A^T q + t. Live: identity, no shift.
    """
    A = np.eye(2) if A is None else np.asarray(A, np.float64)
    img = cv2.GaussianBlur(np.asarray(closeup, np.float32), (0, 0),
                           0.5 * CLOSEUP_PPM / IN_PPM)   # ~1.25 px: no aliasing at 2.5x down
    c = (np.arange(IN_PX) + 0.5) / IN_PPM - CROP_MM / 2
    qx, qy = np.meshgrid(c, -c)
    ox = A[0, 0] * qx + A[1, 0] * qy + t[0]              # A^T q + t
    oy = A[0, 1] * qx + A[1, 1] * qy + t[1]
    # report.closeup: pixel u shows offset (u - 240) / 20, so no half-pixel shift
    mx = (CLOSEUP_PX / 2 + ox * CLOSEUP_PPM).astype(np.float32)
    my = (CLOSEUP_PX / 2 - oy * CLOSEUP_PPM).astype(np.float32)
    return cv2.remap(img, mx, my, cv2.INTER_LINEAR, borderMode=cv2.BORDER_REFLECT)


def stack(before, after):
    """(3, IN_PX, IN_PX) float32 input from two sampled views (0-255)."""
    b, a = before / 255.0, after / 255.0
    return np.stack([b, a, a - b]).astype(np.float32)


def softmax(logits):
    z = logits.reshape(-1).astype(np.float64)
    z = np.exp(z - z.max())
    return (z / z.sum()).reshape(GRID, GRID)


def ring_probabilities(p, centre_mm, spec, mark_mm, sub=4):
    """
    P(ring) for a heatmap p whose crop is centred at centre_mm (target mm): each
    cell's probability spread evenly over sub x sub points, each point scored as
    a hole there would be. Returns {ring: probability}, rings with >= 0.5%.
    """
    offs = cell_offsets()
    s = (np.arange(sub) + 0.5) / sub * CELL_MM - CELL_MM / 2
    out = {}
    keep = p > 1e-4
    for (i, j) in zip(*np.nonzero(keep)):
        w = p[i, j] / (sub * sub)
        for dx in s:
            for dy in s:
                x = centre_mm[0] + offs[i, j, 0] + dx
                y = centre_mm[1] + offs[i, j, 1] + dy
                ring = scoring.score_xy(x, y, spec, pellet_mm=mark_mm)["integer"]
                out[ring] = out.get(ring, 0.0) + w
    total = sum(out.values()) or 1.0
    return {r: v / total for r, v in sorted(out.items(), reverse=True) if v / total >= 0.005}


def read(p, centre_mm, spec, mark_mm, sigma_scale=1.0):
    """The heatmap as a shot estimate (target mm)."""
    offs = cell_offsets()
    mean = (p[..., None] * offs).sum((0, 1))
    d = offs - mean
    var = (p * (d ** 2).sum(-1)).sum() / 2.0               # per axis
    x, y = centre_mm[0] + mean[0], centre_mm[1] + mean[1]
    s = scoring.score_xy(x, y, spec, pellet_mm=mark_mm)
    rings = ring_probabilities(p, centre_mm, spec, mark_mm)
    i, j = np.unravel_index(int(p.argmax()), p.shape)
    return {
        "x_mm": round(float(x), 3), "y_mm": round(float(y), 3),
        "sigma_mm": round(float(math.sqrt(var) * sigma_scale), 3),
        "ring": int(s["integer"]), "decimal": float(s["decimal"]),
        "p_ring": round(float(rings.get(int(s["integer"]), 0.0)), 3),
        "rings": {str(k): round(v, 3) for k, v in rings.items()},
        # distance from the mean to the single most likely cell: large = two
        # places compete (a tear's two ends, an old hole)
        "split_mm": round(float(np.hypot(*(offs[i, j] - mean))), 2),
    }


class HoleModel:
    """The ONNX model, run by cv2.dnn. load() returns None when there is none."""

    def __init__(self, onnx_path, meta):
        self.net = cv2.dnn.readNetFromONNX(str(onnx_path))
        self.meta = meta
        self.version = meta.get("version", "?")

    @classmethod
    def load(cls, path=None):
        path = Path(path) if path else MODEL_DIR / "hole.onnx"
        meta_path = path.with_suffix(".json")
        if not path.exists():
            return None
        meta = json.loads(meta_path.read_text()) if meta_path.exists() else {}
        return cls(path, meta)

    def heatmap(self, before_jpeg, after_jpeg):
        x = stack(sample(decode_jpeg(before_jpeg)), sample(decode_jpeg(after_jpeg)))
        self.net.setInput(x[None])
        return softmax(self.net.forward())

    def estimate(self, before_jpeg, after_jpeg, centre_mm, spec, mark_mm):
        p = self.heatmap(before_jpeg, after_jpeg)
        out = read(p, centre_mm, spec, mark_mm, self.meta.get("sigma_scale", 1.0))
        out["version"] = self.version
        return out
