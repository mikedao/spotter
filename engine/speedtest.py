"""
How fast THIS computer runs the engine - to compare machines (the MacBook Neo vs
the Mac Studio, 2026-11-12) and to catch a machine that slows down as it warms up.
No camera needed: synthetic cards (selftest.render_card), the engine's own code.

    ./.venv/bin/python speedtest.py                       # the engine's steps, ~30 s
    ./.venv/bin/python speedtest.py --stream http://spotter.local:8080/stream
    ./.venv/bin/python speedtest.py --sustain 120         # + 2 min flat out: does it slow down?
    ./.venv/bin/python speedtest.py --save out/speed-neo.json
    ./.venv/bin/python speedtest.py --compare out/speed-neo.json out/speed-studio.json

The per-shot estimates add the steps up the way the engine does them (camera-found
shot: two sightings then the score; heard shot: the 1 s settle, then the score).
"""
import argparse
import contextlib
import io
import json
import os
import platform
import subprocess
import sys
import time
import types

import numpy as np

sys.argv, _argv = ["phase1.py"], sys.argv          # phase1 parses nothing on import
import phase1                                       # noqa: E402
import geometry                                     # noqa: E402
import target0                                      # noqa: E402
import report                                       # noqa: E402
import selftest                                     # noqa: E402
from scoring import PISTOL                          # noqa: E402
sys.argv = _argv


def machine():
    def sh(cmd):
        try:
            return subprocess.run(cmd, capture_output=True, text=True, timeout=5).stdout.strip()
        except Exception:
            return ""
    import cv2
    return {"model": sh(["sysctl", "-n", "hw.model"]) or platform.machine(),
            "chip": sh(["sysctl", "-n", "machdep.cpu.brand_string"]) or platform.processor(),
            "cores": os.cpu_count(),
            "memory_gb": round(int(sh(["sysctl", "-n", "hw.memsize"]) or 0) / 2**30),
            "host": platform.node(), "python": platform.python_version(),
            "opencv": cv2.__version__, "when": time.strftime("%Y-%m-%d %H:%M")}


def timed(fn, n):
    """Median seconds of n runs (after one warm-up), and the last result."""
    out = None
    with contextlib.redirect_stdout(io.StringIO()):
        out = fn()
    ts = []
    for _ in range(n):
        t = time.perf_counter()
        with contextlib.redirect_stdout(io.StringIO()):
            out = fn()
        ts.append(time.perf_counter() - t)
    return float(np.median(ts)), out


def steps(n):
    before, _ = selftest.render_card(30.0, D_mm=300.0)
    after, _ = selftest.render_card(30.0, D_mm=300.0, holes_mm=[(10.0, -6.0)])
    r = {}
    r["fit"], (tf_b, _) = timed(lambda: phase1.establish(before, PISTOL, verbose=False), n)
    _, (tf_a, _) = timed(lambda: phase1.establish(after, PISTOL, verbose=False), 1)
    half = before[::2, ::2].copy()
    r["fit_half"], _ = timed(lambda: phase1.establish(half, PISTOL, verbose=False), n)
    r["register"], reg = timed(lambda: geometry.register(before, tf_b, tf_a, after.shape), n)
    r["difference"], d = timed(lambda: geometry.new_light(after, reg), n)
    r["find_holes"], _ = timed(lambda: target0.detect_holes(d, tf_a.mm_per_px, min_mm=2.0,
                                                              min_circularity=0.30), n)
    r["moving_check"], _ = timed(lambda: phase1._scene_moving(before, tf_b, after, tf_a, PISTOL), n)
    args = types.SimpleNamespace(rule="pellet", verbose=False, frames=1, expect=None, target="pistol")
    r["score_pair"], res = timed(lambda: phase1._score_pair(args, PISTOL, before, tf_b, after, 1, tf=tf_a,
                                                            verbose=False, prior=[]), n)
    assert res and res.get("found"), "the synthetic hole was not found - the benchmark is broken"
    r["png_frame"], _ = timed(lambda: report.png(after), n)          # the picture lane's work
    r["closeup_jpeg"], _ = timed(lambda: report.jpeg(report.closeup(after, tf_a, (10.0, -6.0))), n)
    return r


def stream(url, n):
    with contextlib.redirect_stdout(io.StringIO()):
        cam = phase1._LiveCamera(url)
    try:
        time.sleep(3)
        out = {}
        for k in (1, 2):
            ts = []
            for _ in range(n):
                t = time.perf_counter()
                cam.grab(k)
                ts.append(time.perf_counter() - t)
                time.sleep(0.2)
            out[f"grab_{k}"] = float(np.median(ts))
        return out
    finally:
        cam.close()


def sustain(seconds):
    """Full fits back to back for `seconds`: the first 15 s against the last 15 s.
    A fanless laptop that throttles as it heats shows it here."""
    img, _ = selftest.render_card(30.0, D_mm=300.0)
    t0, rows = time.time(), []
    while time.time() - t0 < seconds:
        t = time.perf_counter()
        with contextlib.redirect_stdout(io.StringIO()):
            phase1.establish(img, PISTOL, verbose=False)
        rows.append((time.time() - t0, time.perf_counter() - t))
    first = [d for t, d in rows if t < 15] or [rows[0][1]]
    last = [d for t, d in rows if t > seconds - 15] or [rows[-1][1]]
    return {"seconds": seconds, "fits": len(rows),
            "first_15s": float(np.median(first)), "last_15s": float(np.median(last))}


def estimates(r, grab1):
    """Seconds per shot, adding the steps up the way the engine does them now."""
    check = grab1 + r["fit"] + r["register"] + r["difference"] + r["find_holes"] + r["moving_check"]
    score = grab1 + r["fit"] + r["moving_check"] + r["score_pair"]
    return {"camera_check": check,
            "camera_found_shot": 0.5 + 2 * check + score,     # wait for a check, two sightings, score
            "heard_shot": phase1.TRIGGER_MS / 1000 + 1.0 + score}   # trigger, settle, score


LABELS = [("fit", "find the target (full fit)"), ("fit_half", "  ...at half size"),
          ("register", "register before onto after"), ("difference", "difference"),
          ("find_holes", "find holes"), ("moving_check", "movement check"),
          ("score_pair", "score the new hole"), ("png_frame", "encode a full frame (PNG)"),
          ("closeup_jpeg", "make a close-up (JPEG)"),
          ("grab_1", "stream: wait for 1 new frame"), ("grab_2", "stream: wait for 2 new frames"),
          ("camera_check", "one camera check"), ("camera_found_shot", "PER SHOT: found by the camera"),
          ("heard_shot", "PER SHOT: heard (1 s settle)")]


def flat(res):
    out = dict(res["steps"])
    out.update(res.get("stream") or {})
    out.update(res["estimates"])
    return out


def show(res):
    m = res["machine"]
    print(f"\n  {m['host']} - {m['model']}, {m['chip']}, {m['cores']} cores, {m['memory_gb']} GB "
          f"(Python {m['python']}, OpenCV {m['opencv']}) - {m['when']}\n")
    f = flat(res)
    for key, label in LABELS:
        if key in f:
            print(f"  {label:36s} {f[key] * 1000:7.0f} ms")
    if res.get("sustain"):
        s = res["sustain"]
        change = (s["last_15s"] / s["first_15s"] - 1) * 100
        print(f"\n  {s['seconds']} s flat out ({s['fits']} fits): first 15 s {s['first_15s'] * 1000:.0f} ms, "
              f"last 15 s {s['last_15s'] * 1000:.0f} ms a fit ({change:+.0f}%"
              f"{' - SLOWING DOWN, likely heat' if change > 15 else ''})")
    if not res.get("stream"):
        print("\n  (per-shot figures assume a 0.25 s frame wait; add --stream URL to measure it)")
    print()


def compare(a, b):
    fa, fb = flat(a), flat(b)
    na, nb = a["machine"]["host"], b["machine"]["host"]
    print(f"\n  {'':36s} {na[:12]:>12s} {nb[:12]:>12s}   {nb[:12]} vs {na[:12]}")
    for key, label in LABELS:
        if key in fa and key in fb:
            print(f"  {label:36s} {fa[key] * 1000:9.0f} ms {fb[key] * 1000:9.0f} ms   "
                  f"{fa[key] / fb[key]:5.2f}x {'faster' if fb[key] < fa[key] else 'slower'}")
    for res, name in ((a, na), (b, nb)):
        if res.get("sustain"):
            s = res["sustain"]
            print(f"  {name}: sustained fits {s['first_15s'] * 1000:.0f} -> {s['last_15s'] * 1000:.0f} ms")
    print()


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--runs", type=int, default=7, help="runs per step (median)")
    p.add_argument("--stream", help="also time frames from this stream URL (the Pi)")
    p.add_argument("--sustain", type=int, default=0, help="seconds of back-to-back fits (try 120)")
    p.add_argument("--save", help="write the results as JSON, for --compare")
    p.add_argument("--compare", nargs=2, metavar=("A.json", "B.json"))
    a = p.parse_args()
    if a.compare:
        compare(*(json.load(open(f)) for f in a.compare))
        return
    print("  timing the engine's steps on synthetic cards...", flush=True)
    res = {"machine": machine(), "steps": steps(a.runs)}
    if a.stream:
        print("  timing the stream...", flush=True)
        res["stream"] = stream(a.stream, a.runs)
    res["estimates"] = estimates(res["steps"], (res.get("stream") or {}).get("grab_1", 0.25))
    if a.sustain:
        print(f"  {a.sustain} s flat out...", flush=True)
        res["sustain"] = sustain(a.sustain)
    show(res)
    if a.save:
        json.dump(res, open(a.save, "w"), indent=1)
        print(f"  saved {a.save}\n")


if __name__ == "__main__":
    main()
