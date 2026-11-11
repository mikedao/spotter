#!/usr/bin/env python3
"""
List every camera this Mac can see and work out which OpenCV index is which.

macOS reports camera NAMES via system_profiler, but OpenCV addresses cameras by
integer INDEX and won't tell you the name. So we do both: print the system's
name list, then probe each index and save a snapshot you can eyeball.

    ./.venv/bin/python cameras.py

Then look at out/cam_<N>.png and use the winning index:

    ./.venv/bin/python target0.py preview --device 2

For the web app's camera picker:

    ./.venv/bin/python cameras.py --json DIR

prints JSON on stdout and writes a small preview JPEG per camera into DIR.
"""
import json
import signal
import subprocess
import sys
from pathlib import Path

import cv2

OUT = Path(__file__).resolve().parent / "out"
MAX_INDEX = 8
PER_CAM_TIMEOUT = 12


class Timeout(Exception):
    pass


def _raise(*_):
    raise Timeout()


def system_names():
    """Ask macOS for the camera names it knows about."""
    try:
        raw = subprocess.run(
            ["system_profiler", "-json", "SPCameraDataType"],
            capture_output=True, text=True, timeout=25).stdout
        items = json.loads(raw).get("SPCameraDataType", [])
        return [it.get("_name", "?") for it in items]
    except Exception as e:
        print(f"  (system_profiler unavailable: {e})")
        return []


def probe(idx):
    """Open one index, grab a frame, save it. Returns a row dict or None."""
    signal.signal(signal.SIGALRM, _raise)
    signal.alarm(PER_CAM_TIMEOUT)
    cap = None
    try:
        cap = cv2.VideoCapture(idx)
        if not cap.isOpened():
            return None
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1920)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 1080)
        for _ in range(8):          # let exposure settle
            cap.read()
        ok, frame = cap.read()
        if not ok or frame is None:
            return None
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        OUT.mkdir(exist_ok=True)
        path = OUT / f"cam_{idx}.png"
        cv2.imwrite(str(path), frame)
        return {
            "index": idx,
            "w": frame.shape[1],
            "h": frame.shape[0],
            "mean": float(gray.mean()),
            "focus": float(cv2.Laplacian(gray, cv2.CV_64F).var()),
            "path": path,
        }
    except Timeout:
        print(f"  index {idx}: timed out after {PER_CAM_TIMEOUT}s, skipping", file=sys.stderr)
        return None
    except Exception as e:
        print(f"  index {idx}: error {e}", file=sys.stderr)
        return None
    finally:
        signal.alarm(0)
        if cap is not None:
            cap.release()


def json_mode(out_dir):
    """For the web app's camera picker: probe every index, write a small preview
    per camera into out_dir, print JSON. macOS's names are only a hint - their
    order usually, not always, matches OpenCV's indices - so the web app shows
    the PICTURES and the shooter picks the one pointed at the target."""
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    names = system_names()
    cams = []
    for i in range(MAX_INDEX):
        r = probe(i)
        if not r:
            continue
        frame = cv2.imread(str(r["path"]))
        thumb = cv2.resize(frame, (640, int(640 * frame.shape[0] / frame.shape[1])))
        name = f"cam_{i}.jpg"
        cv2.imwrite(str(out_dir / name), thumb, [cv2.IMWRITE_JPEG_QUALITY, 80])
        cams.append({"index": i, "width": r["w"], "height": r["h"],
                     "brightness": round(r["mean"], 1),
                     "name_hint": names[i] if i < len(names) else None,
                     "preview": name})
    print(json.dumps({"names": names, "cameras": cams, "microphones": microphones()}))


def microphones():
    """Audio inputs by name (the engine's --mic matches on the name)."""
    try:
        import sounddevice as sd
        return [{"name": d["name"], "channels": int(d["max_input_channels"]),
                 "sample_rate": int(d["default_samplerate"])}
                for d in sd.query_devices() if d["max_input_channels"] > 0]
    except Exception as e:                      # no audio stack: cameras still work
        print(f"  (could not list microphones: {e})", file=sys.stderr)
        return []


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--json":
        json_mode(sys.argv[2])
        return
    print("\nCamera names known to macOS")
    print("-" * 62)
    names = system_names()
    if names:
        for i, n in enumerate(names):
            print(f"  {i}: {n}")
        print("\n  NOTE: this order usually matches OpenCV's indices, but it is")
        print("  not guaranteed. Trust the snapshots below, not this order.")
    else:
        print("  none reported")

    print(f"\nProbing OpenCV indices 0..{MAX_INDEX - 1}")
    print("-" * 62)
    rows = [r for i in range(MAX_INDEX) if (r := probe(i))]

    if not rows:
        sys.exit("\nNo cameras responded. If one is in use by another app "
                 "(Zoom, Photo Booth, FaceTime), quit it and retry.\n")

    print(f"\n{'idx':>4}  {'resolution':>11}  {'mean':>6}  {'focus':>8}  snapshot")
    print("-" * 62)
    for r in rows:
        print(f"{r['index']:>4}  {r['w']:>5}x{r['h']:<5}  {r['mean']:>6.1f}  "
              f"{r['focus']:>8.1f}  {r['path'].name}")

    print(f"""
Open the snapshots in {OUT}/ and find the one showing your target:

    open {OUT}

Then use that index everywhere:

    ./.venv/bin/python target0.py preview   --device N
    ./.venv/bin/python target0.py calibrate --device N

`calibrate` records the index in calib.json, so `jitter` and `detect` pick it
up automatically afterwards.

  'mean'  is average brightness - a lens cap or blocked camera reads very low.
  'focus' is only comparable between cameras pointed at the SAME scene, so
          ignore it here; it is for the sweep in `preview`.
""")


if __name__ == "__main__":
    main()
