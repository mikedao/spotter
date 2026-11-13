#!/usr/bin/env python3
"""
Trains the hole locator (holemodel.py) on the shooter's calls and checks it
against the rules on shots it did NOT train on.

    cd engine
    ml/.venv/bin/python ml/train.py                 # cross-validate, then train on all + export
    ml/.venv/bin/python ml/train.py --cv-only       # just the honest comparison
    ml/.venv/bin/python ml/train.py --steps 300     # quick smoke run

Needs `bin/rails ml:export` first (out/ml/dataset). Writes out/ml/model/hole.onnx
+ hole.json (what the engine loads; the previous model is kept as hole-prev.*).

HONEST NUMBERS: held-out shots are grouped by SESSION (by card while there are
fewer than 3 sessions), never single shots - shots on one card share paper,
light and old holes, so a random split flatters the model.

Labels, per call kind (TrainingExport):
  tapped     the tap is the target position (weight 1)
  accepted   the rules' position is the target (weight 0.5: it looked right,
             it wasn't placed)
  ring_only  no position; only the ring term below
and for every call, a ring term: the probability the heatmap puts inside the
called ring is pushed up.
"""
import argparse
import copy
import json
import math
import shutil
import sys
import time
from pathlib import Path

ENGINE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ENGINE))

import cv2                      # noqa: E402
import numpy as np              # noqa: E402
import torch                    # noqa: E402
import torch.nn as nn           # noqa: E402
import torch.nn.functional as F  # noqa: E402

import holemodel as hm          # noqa: E402
import mleval                   # noqa: E402
import scoring                  # noqa: E402

TARGET_SD_MM = 0.35     # spread of the target heatmap around a label
SHIFT_MM = 1.5          # augmentation: the crop wanders this far from the rules' position
ACCEPTED_WEIGHT = 0.5
RING_WEIGHT = 0.5
FLAG_P = 0.9            # the model flags a shot when its ring is less likely than this


# --- the network: small, fully convolutional, cv2.dnn-friendly ops only ---

def block(i, o, stride):
    return nn.Sequential(
        nn.Conv2d(i, o, 3, stride, 1, bias=False), nn.BatchNorm2d(o), nn.ReLU(inplace=True),
        nn.Conv2d(o, o, 3, 1, 1, bias=False), nn.BatchNorm2d(o), nn.ReLU(inplace=True))


class HoleNet(nn.Module):
    """160 px in -> 40x40 logits (stride 4), with a stride-16 branch for context
    (an old hole, the whole tear) brought back up and joined in."""

    def __init__(self):
        super().__init__()
        self.e1 = block(3, 16, 1)      # 160
        self.e2 = block(16, 32, 2)     # 80
        self.e3 = block(32, 48, 2)     # 40
        self.e4 = block(48, 64, 2)     # 20
        self.e5 = block(64, 64, 2)     # 10
        self.up = nn.Upsample(scale_factor=4, mode="nearest")
        self.head = nn.Sequential(
            nn.Conv2d(48 + 64, 48, 3, 1, 1), nn.ReLU(inplace=True), nn.Conv2d(48, 1, 1))

    def forward(self, x):
        f3 = self.e3(self.e2(self.e1(x)))
        f5 = self.e5(self.e4(f3))
        return self.head(torch.cat([f3, self.up(f5)], 1))


# --- data ---

def load(dataset):
    labels = []
    for lb in mleval.load(dataset):
        imgs = lb.get("images") or {}
        if "after" not in imgs or "before" not in imgs or not lb.get("closeup"):
            continue
        folder = Path(dataset) / "shots" / f"{lb['shot_id']:06d}"
        lb["_before"] = cv2.imread(str(folder / "before.jpg"), cv2.IMREAD_GRAYSCALE).astype(np.float32)
        lb["_after"] = cv2.imread(str(folder / "after.jpg"), cv2.IMREAD_GRAYSCALE).astype(np.float32)
        labels.append(lb)
    return labels


def target_offset(lb):
    """The labelled position as an offset from the close-up centre (mm), or None."""
    c = lb["closeup"]["centre"]
    kind = lb["call"].get("kind")
    if kind == "tapped":
        x, y = lb["call"]["x_mm"], lb["call"]["y_mm"]
    elif kind == "accepted" and lb["proposal"]["x_mm"] is not None:
        x, y = lb["proposal"]["x_mm"], lb["proposal"]["y_mm"]
    else:
        return None, 0.0
    return np.array([x - c[0], y - c[1]]), (1.0 if kind == "tapped" else ACCEPTED_WEIGHT)


def rings_vec(x, y, spec, mark):
    """scoring.score's integer ring, vectorised (checked against it in main)."""
    r_edge = np.maximum(0.0, np.hypot(x, y) - mark / 2.0)
    ten_r = spec.ten_radius_mm
    steps = (r_edge - ten_r) / spec.step_mm
    return np.where(r_edge <= ten_r, 10, np.maximum(0, 10 - np.ceil(steps))).astype(int)


OFFS = hm.cell_offsets()


def example(lb, rng):
    """One augmented sample: input, target heatmap, position, weight, ring mask."""
    theta = rng.uniform(0, 2 * math.pi)
    R = np.array([[math.cos(theta), -math.sin(theta)], [math.sin(theta), math.cos(theta)]])
    A = R @ np.diag([1.0, -1.0]) if rng.random() < 0.5 else R
    t = rng.uniform(-SHIFT_MM, SHIFT_MM, 2)
    gain, bias = rng.uniform(0.9, 1.1), rng.uniform(-10, 10)
    b = hm.sample(lb["_before"], A, t) * gain + bias
    a = hm.sample(lb["_after"], A, t) * gain + bias
    x = hm.stack(b, a)

    off, w = target_offset(lb)
    heat = np.zeros((hm.GRID, hm.GRID), np.float32)
    q = np.zeros(2, np.float32)
    if off is not None:
        q = A @ (off - t)                                   # into the augmented frame
        if np.all(np.abs(q) < hm.CROP_MM / 2 - 0.5):
            d2 = ((OFFS - q) ** 2).sum(-1)
            heat = np.exp(-d2 / (2 * TARGET_SD_MM ** 2)).astype(np.float32)
            heat /= heat.sum()
        else:
            w = 0.0
    # each cell's ring, at the target position it shows (A^T q + t + centre)
    c = lb["closeup"]["centre"]
    ox = A[0, 0] * OFFS[..., 0] + A[1, 0] * OFFS[..., 1] + t[0] + c[0]
    oy = A[0, 1] * OFFS[..., 0] + A[1, 1] * OFFS[..., 1] + t[1] + c[1]
    spec = scoring.SPECS[lb["target"]]
    mask = (rings_vec(ox, oy, spec, mleval.mark_mm(lb)) == mleval.true_ring(lb)).astype(np.float32)
    return x, heat, q.astype(np.float32), np.float32(w), mask


def batch(labels, n, rng):
    rows = [example(labels[i], rng) for i in rng.integers(0, len(labels), n)]
    return [torch.from_numpy(np.stack(col)) for col in zip(*rows)]


def loss_fn(logits, heat, q, w, mask):
    logp = F.log_softmax(logits.flatten(1), 1)
    p = logp.exp()
    offs = torch.from_numpy(OFFS.reshape(-1, 2).astype(np.float32)).to(logits.device)
    mean = p @ offs
    ce = -(heat.flatten(1) * logp).sum(1)
    l1 = (mean - q).abs().sum(1)
    ring = -torch.log((p * mask.flatten(1)).sum(1) + 1e-6)
    return ((w * (ce + l1)).sum() / w.sum().clamp(min=1.0)) + RING_WEIGHT * ring.mean()


def device():
    return torch.device("mps" if torch.backends.mps.is_available() else "cpu")


def train(labels, steps, seed=0, log=False):
    torch.manual_seed(seed)
    rng = np.random.default_rng(seed)
    dev = device()
    net = HoleNet().to(dev)
    opt = torch.optim.AdamW(net.parameters(), lr=2e-3, weight_decay=1e-4)
    sched = torch.optim.lr_scheduler.OneCycleLR(opt, max_lr=2e-3, total_steps=steps, pct_start=0.1)
    net.train()
    t0 = time.time()
    for step in range(steps):
        xs = [v.to(dev) for v in batch(labels, 32, rng)]
        loss = loss_fn(net(xs[0]), *xs[1:])
        opt.zero_grad()
        loss.backward()
        opt.step()
        sched.step()
        if log and (step % 200 == 0 or step == steps - 1):
            print(f"    step {step:>5}  loss {loss.item():.3f}  ({time.time() - t0:.0f} s)", flush=True)
    net.eval()
    return net


@torch.no_grad()
def predict(net, labels, sigma_scale=1.0):
    dev = next(net.parameters()).device
    out = []
    for lb in labels:
        x = hm.stack(hm.sample(lb["_before"]), hm.sample(lb["_after"]))
        logits = net(torch.from_numpy(x[None]).to(dev)).cpu().numpy()
        spec = scoring.SPECS[lb["target"]]
        out.append(hm.read(hm.softmax(logits), lb["closeup"]["centre"], spec, mleval.mark_mm(lb), sigma_scale))
    return out


def groups(labels):
    sessions = {lb["session_id"] for lb in labels}
    key = (lambda lb: lb["session_id"]) if len(sessions) >= 3 else (lambda lb: (lb["session_id"], lb["card"]))
    keys = sorted({key(lb) for lb in labels}, key=str)
    return key, keys, ("session" if len(sessions) >= 3 else "card")


def sigma_scale(labels, preds):
    """Scale the heatmap's spread so a tapped shot's error is ~1 sigma per axis."""
    z2 = [((p["x_mm"] - lb["call"]["x_mm"]) ** 2 + (p["y_mm"] - lb["call"]["y_mm"]) ** 2) / (2 * p["sigma_mm"] ** 2)
          for lb, p in zip(labels, preds) if lb["call"].get("kind") == "tapped" and p["sigma_mm"] > 0]
    return float(math.sqrt(np.median(z2) / 0.693)) if z2 else 1.0  # median of chi2(2)/2 = ln 2


def cross_validate(labels, steps):
    key, keys, by = groups(labels)
    print(f"\nCROSS-VALIDATION: {len(keys)} folds by {by} ({len(labels)} shots), {steps} steps each")
    preds = {}
    for k in keys:
        test = [lb for lb in labels if key(lb) == k]
        train_set = [lb for lb in labels if key(lb) != k]
        t0 = time.time()
        net = train(train_set, steps, seed=len(preds))
        for lb, p in zip(test, predict(net, test)):
            preds[lb["shot_id"]] = p
        print(f"  held out {by} {k}: {len(test)} shots ({time.time() - t0:.0f} s)", flush=True)
    return [preds[lb["shot_id"]] for lb in labels]


def export(net, labels, cv, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    for ext in (".onnx", ".json"):
        cur = path.with_suffix(ext)
        if cur.exists():
            shutil.copy2(cur, path.with_name("hole-prev" + ext))
    net = net.cpu().eval()
    x = torch.from_numpy(hm.stack(hm.sample(labels[0]["_before"]), hm.sample(labels[0]["_after"]))[None])
    torch.onnx.export(net, (x,), str(path), input_names=["input"], output_names=["logits"],
                      opset_version=17, dynamo=False)
    # the engine runs it with cv2.dnn: it must give the same heatmap
    dnn = cv2.dnn.readNetFromONNX(str(path))
    dnn.setInput(x.numpy())
    diff = float(np.abs(hm.softmax(dnn.forward()) - hm.softmax(net(x).detach().numpy())).max())
    if diff > 1e-4:
        sys.exit(f"cv2.dnn disagrees with torch by {diff:.2e} - not exporting")
    meta = {"version": time.strftime("%Y%m%d-%H%M"), "trained_on": len(labels),
            "sessions": len({lb["session_id"] for lb in labels}),
            "kinds": {k: sum(lb["call"].get("kind") == k for lb in labels) for k in ("tapped", "accepted", "ring_only")},
            "crop_mm": hm.CROP_MM, "in_ppm": hm.IN_PPM, "grid": hm.GRID, "flag_p": FLAG_P, **cv}
    path.with_suffix(".json").write_text(json.dumps(meta, indent=2) + "\n")
    print(f"\nexported {path} (version {meta['version']}; cv2.dnn matches torch to {diff:.1e})")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dataset", nargs="?", default=str(ENGINE / "out/ml/dataset"))
    ap.add_argument("--steps", type=int, default=1500)
    ap.add_argument("--cv-only", action="store_true")
    ap.add_argument("--out", default=str(hm.MODEL_DIR / "hole.onnx"))
    a = ap.parse_args()

    # the vectorised ring must be scoring.py's ring
    rng = np.random.default_rng(1)
    for spec in scoring.SPECS.values():
        xy = rng.uniform(-80, 80, (2000, 2))
        assert all(rings_vec(x, y, spec, scoring.PELLET_MARK_MM) ==
                   scoring.score_xy(x, y, spec, pellet_mm=scoring.PELLET_MARK_MM)["integer"] for x, y in xy)

    labels = load(a.dataset)
    if len(labels) < 20:
        sys.exit(f"only {len(labels)} called shots with close-ups - not enough to train on")
    print(f"{len(labels)} called shots with close-ups, training on {device()}")

    oof = cross_validate(labels, a.steps)
    scale = sigma_scale(labels, oof)
    for p in oof:
        p["sigma_mm"] = round(p["sigma_mm"] * scale, 3)
    # the same report as mleval, with the held-out model as one more method
    shown = copy.deepcopy([{k: v for k, v in lb.items() if not k.startswith("_")} for lb in labels])
    for lb, p in zip(shown, oof):
        lb["estimates"]["model"] = p
    s = mleval.summarize(shown)
    mleval.report(s, shown)
    r, m = s["ring"]["rules"], s["ring"]["model"]
    cv = {"cv": {"by": groups(labels)[2], "rules_agree": r["agree"], "model_agree": m["agree"], "n": m["n"],
                 "model_median_mm": s["position"]["model"].get("median_mm"),
                 "rules_median_mm": s["position"]["rules"].get("median_mm"),
                 "model_flags": s["flags_model"]}, "sigma_scale": scale}
    if a.cv_only:
        return

    print(f"\nTRAINING on all {len(labels)} shots")
    net = train(labels, a.steps, log=True)
    export(net, labels, cv, Path(a.out))


if __name__ == "__main__":
    main()
