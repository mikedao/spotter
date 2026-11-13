#!/usr/bin/env python3
"""
How well do the scoring RULES agree with the shooter's calls? The baseline a
learned model has to beat, measured on the web app's export (bin/rails ml:eval,
which runs this after writing the export; or by hand):

    ./.venv/bin/python mleval.py out/ml/dataset            # the report
    ./.venv/bin/python mleval.py out/ml/dataset --save     # + append to the history
    ./.venv/bin/python mleval.py out/ml/dataset --json     # the summary as JSON

Each label's call is one of three kinds (TrainingExport#call_kind):
  tapped     the shooter placed the hole - position error is measured on these
  accepted   no tap, the rules' ring kept - confirms the ring only
  ring_only  no tap, a different ring
Shooters tap mostly where the rules look off, so the position numbers (tapped
shots only) overstate the rules' error over ALL shots; ring agreement uses every
call and is the headline. Shots scored by hand (pinpointed) have no rules'
proposal and are left out of the rules' numbers.

Methods compared, each scored with the session's rule (pellet = the 5.8 mm mark):
  rules       what the engine announced (centroid; circle fit on an overlap)
  centroid    the region's centroid
  circle fit  the 4.5 mm circle fit where it found enough round edge, else centroid
"""
import argparse
import json
import math
import statistics
import sys
import time
from pathlib import Path

import scoring

WRONG_SPOT_MM = 3.0     # a tap this far off = the rules picked the wrong spot, not a line call


def load(dataset):
    index = Path(dataset) / "index.jsonl"
    if not index.exists():
        sys.exit(f"no {index} - run `bin/rails ml:export` in web/ first")
    return [json.loads(line) for line in index.read_text().splitlines() if line.strip()]


def mark_mm(label):
    return scoring.PELLET_MM if label.get("rule") == "gauge" else scoring.PELLET_MARK_MM


def ring_at(label, xy, mark=None):
    spec = scoring.SPECS[label["target"]]
    s = scoring.score_xy(xy[0], xy[1], spec, pellet_mm=mark or mark_mm(label))
    return s["integer"], s["decimal"]


def true_ring(label):
    c = label["call"]
    return c["ring"] if c["ring"] is not None else label["proposal"]["ring"]


def tap(label):
    c = label["call"]
    return (c["x_mm"], c["y_mm"]) if c.get("kind") == "tapped" else None


# --- the positions each method proposes (None = it has none for this shot) ---

def pos_rules(label):
    p = label["proposal"]
    return (p["x_mm"], p["y_mm"]) if p["x_mm"] is not None else None


def pos_centroid(label):
    c = label["estimates"].get("centroid")
    return tuple(c) if c else pos_rules(label)


def pos_circle(label):
    f = label["estimates"].get("circle_fit") or {}
    return (f["x"], f["y"]) if f.get("ok") else pos_centroid(label)


def pos_model(label):
    m = label["estimates"].get("model")
    return (m["x_mm"], m["y_mm"]) if m else None


# "model" = the learned locator (holemodel.py): live in the engine (shadow mode,
# estimates.model), or held out in ml/train.py's cross-validation. Shots without
# it are left out of its numbers (see its n).
METHODS = {"rules": pos_rules, "centroid": pos_centroid, "circle fit": pos_circle, "model": pos_model}
FLAG_P = 0.9            # the model flags a shot whose ring it gives less than this


def wilson(k, n, z=1.96):
    """95% interval for a rate k/n (sound at small n and near 100%)."""
    if n == 0:
        return (0.0, 0.0)
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (max(0.0, c - h), min(1.0, c + h))


def pct(q, xs):
    xs = sorted(xs)
    if not xs:
        return float("nan")
    i = (len(xs) - 1) * q
    lo, hi = math.floor(i), math.ceil(i)
    return xs[lo] + (xs[hi] - xs[lo]) * (i - lo)


def ring_stats(labels, method):
    agree = higher = lower = n = 0
    for lb in labels:
        if method == "rules":
            ring = lb["proposal"]["ring"]
        else:
            pos = METHODS[method](lb)
            if pos is None:
                continue
            ring = ring_at(lb, pos)[0]
        n += 1
        t = true_ring(lb)
        agree += ring == t
        higher += ring > t
        lower += ring < t
    return {"n": n, "agree": agree, "rate": agree / n if n else None,
            "ci95": wilson(agree, n), "higher": higher, "lower": lower}


def position_stats(labels, method):
    errs, radial = [], []
    for lb in labels:
        t = tap(lb)
        p = METHODS[method](lb)
        if not t or not p:
            continue
        errs.append(math.dist(p, t))
        radial.append(math.hypot(*p) - math.hypot(*t))
    if not errs:
        return {"n": 0}
    return {"n": len(errs), "median_mm": statistics.median(errs), "p90_mm": pct(0.9, errs),
            "max_mm": max(errs), "over_1mm": sum(e > 1 for e in errs),
            "wrong_spot": sum(e > WRONG_SPOT_MM for e in errs),
            # engine minus tap, along the radius: + = the rules put holes further out
            "radial_bias_mm": statistics.mean(radial),
            "radial_bias_median_mm": statistics.median(radial)}


def flag_stats(labels):
    flagged = [lb for lb in labels if any(lb["proposal"][k] for k in ("line_call", "ambiguous", "overlap"))]
    changed = [lb for lb in labels if lb["proposal"]["ring"] != true_ring(lb)]
    caught = [lb for lb in changed if lb in flagged]
    return {"flagged": len(flagged), "n": len(labels), "ring_changed": len(changed),
            "caught": len(caught),
            "missed": [lb["shot_id"] for lb in changed if lb not in flagged],
            "flagged_needlessly": len(flagged) - len(caught)}


def model_flag_stats(labels):
    """The model's own flags: its ring less likely than FLAG_P."""
    have = [lb for lb in labels if lb["estimates"].get("model")]
    flagged = [lb for lb in have if lb["estimates"]["model"]["p_ring"] < FLAG_P]
    wrong = [lb for lb in have if ring_at(lb, pos_model(lb))[0] != true_ring(lb)]
    caught = [lb for lb in wrong if lb in flagged]
    return {"flagged": len(flagged), "n": len(have), "wrong": len(wrong), "caught": len(caught),
            "missed": [lb["shot_id"] for lb in wrong if lb not in flagged],
            "flagged_needlessly": len(flagged) - len(caught)}


def mark_sweep(labels):
    """Ring agreement of the rules' POSITION as the touch allowance varies (the
    PELLET_MARK_MM fit, scoring.py). Accepted calls were judged at 0.65, so they
    pull towards it: read the window, not the peak."""
    rows = []
    for i in range(0, 25):
        allowance = i * 0.05
        mark = scoring.PELLET_MM + 2 * allowance
        k = sum(ring_at(lb, pos_rules(lb), mark)[0] == true_ring(lb) for lb in labels)
        rows.append({"allowance_mm": round(allowance, 2), "agree": k})
    best = max(r["agree"] for r in rows)
    window = [r["allowance_mm"] for r in rows if r["agree"] == best]
    return {"rows": rows, "best": best, "window": (min(window), max(window))}


def tap_consistency(labels):
    """Does the shooter's tap score to the ring they called? (Disagreement = a
    ring picked against the tap - the labels' own noise.)"""
    tapped = [lb for lb in labels if tap(lb)]
    off = [lb["shot_id"] for lb in tapped if ring_at(lb, tap(lb))[0] != lb["call"]["ring"]]
    return {"n": len(tapped), "consistent": len(tapped) - len(off), "inconsistent": off}


def worst(labels, n=10):
    rows = []
    for lb in labels:
        t = tap(lb)
        moved = math.dist(pos_rules(lb), t) if t else 0.0
        ring_changed = lb["proposal"]["ring"] != true_ring(lb)
        if ring_changed or moved > 1.0:
            rows.append((ring_changed, moved, lb))
    rows.sort(key=lambda r: (r[0], r[1]), reverse=True)
    return rows[:n]


def summarize(labels):
    rules = [lb for lb in labels if not lb.get("pinpointed")]
    methods = [m for m in METHODS if m == "rules" or any(METHODS[m](lb) for lb in rules)]
    kinds = {k: sum(lb["call"].get("kind") == k for lb in labels) for k in ("tapped", "accepted", "ring_only")}
    return {
        "at": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "shots": len(labels), "pinpointed": len(labels) - len(rules),
        "sessions": len({lb["session_id"] for lb in labels}),
        "kinds": kinds,
        "ring": {m: ring_stats(rules, m) for m in methods},
        "position": {m: position_stats(rules, m) for m in methods},
        "flags": flag_stats(rules),
        "flags_model": model_flag_stats(rules) if "model" in methods else None,
        "mark_sweep": mark_sweep(rules),
        "taps": tap_consistency(labels),
        "per_session": per_session(rules),
    }


def per_session(labels):
    out = []
    for sid in sorted({lb["session_id"] for lb in labels}):
        s = [lb for lb in labels if lb["session_id"] == sid]
        r = ring_stats(s, "rules")
        p = position_stats(s, "rules")
        m = ring_stats(s, "model")
        mp = position_stats(s, "model")
        versions = sorted({lb["estimates"]["model"].get("version") for lb in s if lb["estimates"].get("model")})
        out.append({"session_id": sid, "date": min(lb["fired_at"] for lb in s)[:10],
                    "target": s[0]["target"], "n": len(s), "agree": r["agree"],
                    "tapped": p["n"], "median_mm": p.get("median_mm"),
                    # the model as it ran LIVE in that session (shadow): trained before it
                    "model_n": m["n"], "model_agree": m["agree"],
                    "model_median_mm": mp.get("median_mm"), "model_versions": versions})
    return out


def report(s, labels, previous=None):
    k = s["kinds"]
    print(f"\nSCORING RULES vs YOUR CALLS - {s['shots']} called shots, {s['sessions']} session(s)")
    print(f"  {k['tapped']} tapped, {k['accepted']} accepted as scored, {k['ring_only']} ring changed without a tap"
          + (f"; {s['pinpointed']} scored by hand (left out)" if s["pinpointed"] else ""))

    print("\nRING agreement with your call (every call)")
    for m, r in s["ring"].items():
        lo, hi = r["ci95"]
        print(f"  {m:<11} {r['agree']:>4}/{r['n']:<4} {100 * r['rate']:5.1f}%   95% range {100 * lo:.0f}-{100 * hi:.0f}%"
              f"   engine higher {r['higher']}, lower {r['lower']}")

    print("\nPOSITION vs your tap (tapped shots only - you tap mostly where it looked off)")
    print(f"  {'':<11} {'median':>7} {'p90':>6} {'max':>6}  >1mm  >{WRONG_SPOT_MM:.0f}mm  radial bias (mean / median)")
    for m, p in s["position"].items():
        if not p["n"]:
            print(f"  {m:<11} no tapped shots")
            continue
        print(f"  {m:<11} {p['median_mm']:6.2f}  {p['p90_mm']:5.2f}  {p['max_mm']:5.2f}  {p['over_1mm']:>4}  {p['wrong_spot']:>4}"
              f"  {p['radial_bias_mm']:+.2f} / {p['radial_bias_median_mm']:+.2f} mm")
    print("  (radial bias + = the engine put holes further OUT than you did)")

    f = s["flags"]
    print(f"\nFLAGS: {f['flagged']} of {f['n']} shots flagged; of {f['ring_changed']} ring changes, "
          f"{f['caught']} were flagged" + (f", MISSED: {', '.join(f'/shots/{i}' for i in f['missed'])}" if f["missed"] else ""))
    print(f"  {f['flagged_needlessly']} flagged shots kept their ring")
    fm = s.get("flags_model")
    if fm:
        print(f"  model (P(ring) < {FLAG_P}): {fm['flagged']} of {fm['n']} flagged; of its {fm['wrong']} wrong rings, "
              f"{fm['caught']} flagged" + (f", MISSED: {', '.join(f'/shots/{i}' for i in fm['missed'])}" if fm["missed"] else "")
              + f"; {fm['flagged_needlessly']} flagged needlessly")

    w = s["mark_sweep"]
    print(f"\nTOUCH ALLOWANCE (scoring.PELLET_MARK_MM = 4.5 + 2 x 0.65): rules' positions agree best "
          f"({w['best']}/{s['ring']['rules']['n']}) at {w['window'][0]:.2f}-{w['window'][1]:.2f} mm")

    t = s["taps"]
    if t["inconsistent"]:
        print(f"\nYOUR TAPS: {t['consistent']}/{t['n']} score to the ring you called; not: "
              + ", ".join(f"/shots/{i}" for i in t["inconsistent"]))

    if len(s["per_session"]) > 1:
        print("\nPER SESSION (rules)")
        for r in s["per_session"]:
            med = f"{r['median_mm']:.2f} mm" if r["median_mm"] is not None else "-"
            print(f"  #{r['session_id']:<5} {r['date']}  {r['target']:<6} {r['agree']:>3}/{r['n']:<3} rings   "
                  f"{r['tapped']:>3} tapped, median {med}")

    rows = worst([lb for lb in labels if not lb.get("pinpointed")])
    if rows:
        print("\nWORST (ring changed, or tapped > 1 mm away)")
        for ring_changed, moved, lb in rows:
            p, flags = lb["proposal"], [n for n in ("line_call", "ambiguous", "overlap") if lb["proposal"][n]]
            ring = f"ring {p['ring']} -> {true_ring(lb)}" if ring_changed else f"ring {p['ring']} kept"
            print(f"  /shots/{lb['shot_id']:<6} {ring:<15} moved {moved:5.2f} mm  {lb['call']['kind']:<9} "
                  f"{', '.join(flags) or 'not flagged'}")

    if previous:
        a, b = previous["ring"]["rules"], s["ring"]["rules"]
        print(f"\nSINCE {previous['at']}: {previous['shots']} -> {s['shots']} shots; rules' ring agreement "
              f"{100 * a['rate']:.1f}% -> {100 * b['rate']:.1f}%")
    print()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dataset", nargs="?", default="out/ml/dataset")
    ap.add_argument("--save", action="store_true", help="append the summary to <dataset>/../eval-history.jsonl")
    ap.add_argument("--json", action="store_true", help="print the summary as JSON instead of the report")
    a = ap.parse_args()

    labels = load(a.dataset)
    if not labels:
        sys.exit("no called shots in the export yet")
    s = summarize(labels)
    history = Path(a.dataset).resolve().parent / "eval-history.jsonl"
    previous = None
    if history.exists():
        lines = [line for line in history.read_text().splitlines() if line.strip()]
        previous = json.loads(lines[-1]) if lines else None
    if a.json:
        print(json.dumps(s, indent=2))
    else:
        report(s, labels, previous)
    if a.save:
        with history.open("a") as fh:
            fh.write(json.dumps(s) + "\n")
        print(f"saved to {history}", file=sys.stderr)   # stdout may be --json


if __name__ == "__main__":
    main()
