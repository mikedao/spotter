"""
camtune.py - find a camera's best settings ON THE RIG, and save them.

A camera nobody has tuned yet runs on its own automatics, and a webcam's
autofocus and auto exposure are rarely what scoring wants (the Logitech C920,
2026-11-23: autofocus gave sharpness 16, tuned focus 118; edge fit 0.30 ->
0.06 px). This does what was first done by hand, scored by the ENGINE itself:

  1. read which controls the camera has (v4l2-ctl, on the Pi over ssh or here
     on Linux) - focus, exposure, gain, white balance, under any of their names
  2. focus: autofocus off, a coarse sweep of the whole range, then a fine one
     around the best; pick the sharpest card that also fits best
  3. exposure: manual, longest exposure that clips nothing on the card (within
     the stream's frame time), then gain up until the paper is bright
  4. white balance: let auto settle, then lock what it chose
  5. bench the tuned settings against the camera's automatics (geometry noise,
     phantom shots, contrast) and keep manual unless it is worse
  6. write the settings as a PROFILE, pi/cameras/<vendor>-<product>.conf, and
     put it on the Pi (/etc/spotter/cameras/), where spotter-camera-controls
     applies it on every stream start and camera plug-in (pi/README.md)

Focus depends on the camera-to-card distance and exposure on the light, so a
profile belongs to a RIG: re-run after moving the camera or changing the light.
Needs a CLEAN card in view (holes would be scored as focus detail) and, for the
Pi, ssh without a password (`ssh-copy-id USER@spotter.local`).

    ./.venv/bin/python camtune.py --pi spotter.local
    ./.venv/bin/python camtune.py --pi spotter.local --quick      # ~2 min
    ./.venv/bin/python camtune.py --local /dev/video0 --device 0  # Linux, camera here

A camera on a Mac cannot be tuned: macOS gives no way to set a webcam's
controls from code (AVFoundation), so plug it into the Pi (or any Linux box).
"""
import argparse
import contextlib
import io
import json
import os
import re
import shlex
import socket
import subprocess
import sys
import time
import urllib.request
from datetime import datetime
from pathlib import Path

import cv2
import numpy as np

import phase1
import target0
from scoring import SPECS, decimal_step_mm, ring_radius_mm

ROOT = Path(__file__).resolve().parent.parent
PROFILES = ROOT / "pi" / "cameras"          # in git: tuned profiles, by USB id
PI_PROFILES = "/etc/spotter/cameras"         # on the Pi (install.sh makes it)

# The same control under the names different kernels / cameras use.
NAMES = {
    "focus_auto": ("focus_automatic_continuous", "focus_auto"),
    "focus": ("focus_absolute",),
    "exposure_auto": ("auto_exposure", "exposure_auto"),
    "exposure": ("exposure_time_absolute", "exposure_absolute"),
    "exposure_dynamic": ("exposure_dynamic_framerate", "exposure_auto_priority"),
    "gain": ("gain",),
    "wb_auto": ("white_balance_automatic", "white_balance_temperature_auto"),
    "wb": ("white_balance_temperature",),
    "power_line": ("power_line_frequency",),
}

SETTLE_S = 2.5          # after a change: focus motor / exposure loop, + stream lag
PAPER_LOW = 190         # paper this dark at the longest exposure -> add gain
PAPER_AIM = 215
PAPER_MAX = 240
SAT_MAX_PCT = 0.1       # clipped share of the card allowed


# ---------------------------------------------------------------- controls

class Controls:
    """The camera's V4L2 controls, through v4l2-ctl - on the Pi over ssh
    (one connection, reused) or on this machine. ONE control per call: several
    `-c` in one call left the Kiyo sending black frames (pi/README.md)."""

    def __init__(self, host=None, video="/dev/video0"):
        self.host, self.video = host, video
        # One plain ssh per call (~0.5 s). A shared connection (ControlMaster)
        # was tried: its background master holds captured pipes open, and a
        # restore after Ctrl+C hung on it.
        # The address is looked up ONCE: macOS's mDNS lookup of a .local name
        # took 5-30 s now and then, per ssh call (2026-11-23). HostKeyAlias
        # keeps checking the Pi's key under its name.
        self.ssh = None
        if host:
            user, _, name = host.rpartition("@")
            try:
                ip = socket.getaddrinfo(name, 22, socket.AF_INET)[0][4][0]
            except OSError:
                ip = name
            self.ssh = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8",
                        "-o", f"HostKeyAlias={name}", f"{user}@{ip}" if user else ip]

    def run(self, cmd, check=True):
        args = self.ssh + [cmd] if self.ssh else ["sh", "-c", cmd]
        r = subprocess.run(args, capture_output=True, text=True, timeout=30)
        if check and r.returncode != 0:
            raise RuntimeError(f"{cmd!r}: {(r.stderr or r.stdout).strip()}")
        return r.stdout

    def v4l2(self, args, check=True):
        return self.run(f"v4l2-ctl -d {shlex.quote(self.video)} {args}", check)

    def list(self):
        """{name: {type, min, max, step, default, value, flags, menu{}}}"""
        out, ctrls, cur = self.v4l2("--list-ctrls-menus"), {}, None
        for line in out.splitlines():
            m = re.match(r"\s*(\w+) 0x[0-9a-f]+ \((\w+)\)\s*:(.*)", line)
            if m:
                name, typ, rest = m.groups()
                c = {"type": typ, "menu": {}, "flags": ""}
                for k, v in re.findall(r"(\w+)=(\S+)", rest):
                    c[k] = v if k == "flags" else int(v)
                ctrls[name], cur = c, c
                continue
            m = re.match(r"\s+(\d+): (.+)", line)
            if m and cur is not None:
                cur["menu"][int(m.group(1))] = m.group(2).strip()
        return ctrls

    def set(self, name, value):
        self.v4l2(f"-c {name}={int(value)}")

    def get(self, name):
        out = self.v4l2(f"--get-ctrl={name}")
        return int(re.search(r":\s*(-?\d+)", out).group(1))

    def identity(self):
        """(vendor id, product id, name) from udev, e.g. ('046d', '082d', ...)"""
        out = self.run(f"udevadm info -q property -n {shlex.quote(self.video)}")
        p = dict(l.split("=", 1) for l in out.splitlines() if "=" in l)
        name = p.get("ID_V4L_PRODUCT") or p.get("ID_MODEL", "camera").replace("_", " ")
        return p.get("ID_VENDOR_ID", "0000"), p.get("ID_MODEL_ID", "0000"), name


def pick(ctrls, role):
    """The camera's name for a control role, or None if it has none."""
    return next((n for n in NAMES[role] if n in ctrls), None)


def manual_value(menu):
    """The 'Manual Mode' entry of an auto-exposure menu (1 by the V4L2 spec)."""
    return next((k for k, v in menu.items() if "manual" in v.lower()), 1)


# ---------------------------------------------------------------- measuring

class Rig:
    """The camera's picture of the card, measured as the engine sees it."""

    def __init__(self, device, spec):
        self.spec = spec
        with contextlib.redirect_stdout(io.StringIO()):
            self.cam = phase1._LiveCamera(device)
        self.card = self.black = None

    def close(self):
        self.cam.close()

    def frame(self):
        return self.cam.grab(1, timeout=8.0)

    def masks(self, gray):
        """Card (inside ring 1) and black-centre masks, from one good fit:
        the camera does not move during a run, so the regions don't either."""
        tf, info = self._fit(gray)
        if tf is None:
            return info.get("reason", "the aiming mark was not found")
        H, W = gray.shape
        th = np.linspace(0, 2 * np.pi, 360, endpoint=False)
        r1 = ring_radius_mm(self.spec, 1)
        bx, by = tf.from_mm(r1 * np.cos(th), r1 * np.sin(th))
        card = np.zeros((H, W), np.uint8)
        cv2.fillPoly(card, [np.stack([bx, by], 1).astype(np.int32)], 1)
        self.card = card.astype(bool)
        r = np.hypot(*tf.to_mm(*np.meshgrid(np.arange(W), np.arange(H))))
        self.black = r < 0.8 * self.spec.black_dia_mm / 2.0
        return None

    def _fit(self, gray):
        with contextlib.redirect_stdout(io.StringIO()):
            return phase1.establish(gray, self.spec, verbose=False)

    def measure(self, n=2):
        """Median over n fresh frames: found, edge fit (px), ring fit (mm),
        card sharpness (Laplacian variance inside ring 1), paper / black
        levels, clipped share of the card."""
        rows = []
        for _ in range(n):
            g = self.frame()
            g8 = np.clip(g, 0, 255).astype(np.uint8)
            tf, info = self._fit(g)
            lap = cv2.Laplacian(g8, cv2.CV_64F)
            paper_px = g8[self.card & ~self.black]
            rows.append({
                "found": tf is not None,
                "edge": info.get("edge_rms_px") if tf is not None and info.get("refined") else None,
                "ring": info.get("rms_mm") if tf is not None else None,
                "sharp": float(lap[self.card].var()),
                "paper": float(np.percentile(paper_px, 75)),
                "black": float(np.median(g8[self.black & self.card])),
                "sat": float((g8[self.card] >= 254).mean() * 100),
            })
        out = {"found": sum(r["found"] for r in rows) > n / 2}
        for k in ("edge", "ring", "sharp", "paper", "black", "sat"):
            v = [r[k] for r in rows if r[k] is not None]
            out[k] = round(float(np.median(v)), 4) if v else None
        return out

    def bench(self, rounds):
        frames, tfs, infos = [], [], []
        for _ in range(rounds):
            g = self.frame()
            tf, info = self._fit(g)
            if tf is None:
                continue
            frames.append(g); tfs.append(tf); infos.append(info)
            time.sleep(0.15)
        if len(frames) < 3:
            return None
        return phase1.bench_stats(frames, tfs, infos, self.spec)["row"]


# ---------------------------------------------------------------- the tune

class Lost(RuntimeError):
    """The card went out of sight mid-run (light off, card moved): stop,
    write no profile, put the camera back."""


class Tuner:
    def __init__(self, ctl, rig, quick=False, log=print):
        self.ctl, self.rig, self.quick, self.say = ctl, rig, quick, log
        self.ctrls = ctl.list()
        self.steps = {}                 # role -> sweep rows, for the report
        self.chosen = []                # (control, value) in the order to apply
        self.touched = False            # anything changed on the camera yet

    def has(self, role):
        return pick(self.ctrls, role)

    def set(self, role, value, wait=True):
        name = pick(self.ctrls, role)
        self.touched = True
        self.ctl.set(name, value)
        if wait:
            time.sleep(SETTLE_S)

    def keep(self, role, value):
        name = pick(self.ctrls, role)
        self.chosen = [(n, v) for n, v in self.chosen if n != name] + [(name, int(value))]

    def grid(self, lo, hi, step, points):
        """~points values lo..hi on the control's own step."""
        stride = max(step, int(np.ceil((hi - lo) / max(points - 1, 1) / step)) * step)
        return list(range(lo, hi + 1, stride)) + ([hi] if (hi - lo) % stride else [])

    def sweep(self, role, values, frames, label):
        rows = []
        for v in values:
            self.set(role, v)
            m = self.rig.measure(frames)
            m["value"] = v
            rows.append(m)
            self.say(f"    {label} {v:>5}: " + describe(m))
        self.steps.setdefault(role, []).extend(rows)
        return rows

    # -- focus

    def focus(self):
        if not self.has("focus"):
            self.say("  focus: no manual focus on this camera (fixed focus) - skipped")
            return
        c = self.ctrls[self.has("focus")]
        if self.has("focus_auto"):
            self.set("focus_auto", 0, wait=False)
            self.keep("focus_auto", 0)
        lo, hi, step = c["min"], c["max"], max(c.get("step", 1), 1)
        self.say(f"  focus: sweeping {lo}-{hi} (autofocus off)")
        coarse = self.sweep("focus", self.grid(lo, hi, step, 14 if self.quick else 26),
                            1 if self.quick else 2, "focus")
        best = choose_focus(coarse)
        if best is None:
            raise Lost("the card was not found at ANY focus - is it in view?")
        stride = coarse[1]["value"] - coarse[0]["value"] if len(coarse) > 1 else step
        fine_step = max(step, (stride // 4) // step * step)
        fine_vals = [v for v in range(best - stride, best + stride + 1, fine_step)
                     if lo <= v <= hi and v not in {r["value"] for r in coarse}]
        rows = coarse
        if fine_vals:
            self.say(f"  focus: fine sweep around {best}")
            rows = coarse + self.sweep("focus", fine_vals, 2 if self.quick else 3, "focus")
        best = choose_focus(rows)
        self.set("focus", best)
        self.keep("focus", best)
        self.say(f"  focus: {best}")

    # -- exposure and gain

    def exposure(self, fps):
        if not (self.has("exposure_auto") and self.has("exposure")):
            self.say("  exposure: no manual exposure on this camera - left on auto")
            return
        auto_c = self.ctrls[self.has("exposure_auto")]
        manual = manual_value(auto_c["menu"])
        self.set("exposure_auto", manual, wait=False)
        self.keep("exposure_auto", manual)
        if self.has("exposure_dynamic"):
            # may stretch frames in the dark: a fixed frame rate is wanted
            self.set("exposure_dynamic", 0, wait=False)
            self.keep("exposure_dynamic", 0)
        c = self.ctrls[self.has("exposure")]
        g = self.ctrls.get(self.has("gain") or "", None)
        if g:
            self.set("gain", g["min"], wait=False)
        # exposure is in 100 us units; stay well inside the stream's frame time
        cap = min(c["max"], int(0.7 * 10000 / fps))
        lo = max(c["min"], 10)
        vals = sorted({int(round(v / c.get("step", 1))) * c.get("step", 1)
                       for v in np.geomspace(lo, cap, 6 if self.quick else 9)})
        self.say(f"  exposure: sweeping {vals[0]}-{vals[-1]} (x100 us; manual, gain "
                 f"{g['min'] if g else '-'}; the stream runs {fps:g} fps)")
        rows = self.sweep("exposure", vals, 1 if self.quick else 2, "exposure")
        ok = [r for r in rows if r["found"] and r["sat"] <= SAT_MAX_PCT
              and r["paper"] <= PAPER_MAX]
        if not ok:
            seen = [r for r in rows if r["found"]]
            if not seen:
                raise Lost("the card was not found at ANY exposure - did the light go out?")
            ok = [min(seen, key=lambda r: r["sat"])]     # everything clips: least
        best = max(ok, key=lambda r: r["value"])
        exp = best["value"]
        self.set("exposure", exp)
        self.keep("exposure", exp)
        gain = g["min"] if g else None
        if g and best["paper"] < PAPER_LOW:
            hi = min(g["max"], g["min"] + (g["max"] - g["min"]) // 2)   # past half: noise
            gvals = self.grid(g["min"], hi, max(g.get("step", 1), 1), 5 if self.quick else 8)[1:]
            self.say(f"  gain: the paper reads {best['paper']:.0f} at exposure {exp}; "
                     f"adding gain {gvals[0]}-{gvals[-1]}")
            grows = self.sweep("gain", gvals, 1 if self.quick else 2, "gain")
            okg = [r for r in grows if r["found"] and r["sat"] <= SAT_MAX_PCT
                   and r["paper"] <= PAPER_MAX]
            if okg:
                bright = [r for r in okg if r["paper"] >= PAPER_AIM - 15]
                gain = (min(bright, key=lambda r: r["value"]) if bright
                        else max(okg, key=lambda r: r["value"]))["value"]
        if g:
            self.set("gain", gain)
            self.keep("gain", gain)
        self.say(f"  exposure: {exp}" + (f", gain {gain}" if g else ""))

    # -- white balance

    def white_balance(self):
        if not (self.has("wb_auto") and self.has("wb")):
            self.say("  white balance: no manual white balance - left on auto")
            return
        self.set("wb_auto", 1, wait=False)
        time.sleep(4.0)                         # let auto settle on this light
        self.set("wb_auto", 0, wait=False)      # UVC keeps the value auto chose
        k = self.ctl.get(self.has("wb"))
        self.keep("wb_auto", 0)
        self.keep("wb", k)
        self.say(f"  white balance: locked at {k} K (what auto chose)")

    def automatics(self):
        """The camera left to itself: every auto switch on (the comparison)."""
        out = []
        if self.has("focus_auto"):
            out.append((self.has("focus_auto"), 1))
        if self.has("exposure_auto"):
            menu = self.ctrls[self.has("exposure_auto")]["menu"]
            autos = [k for k, v in menu.items() if "manual" not in v.lower()]
            prio = [k for k in autos if "aperture" in menu[k].lower()]
            if prio or autos:
                out.append((self.has("exposure_auto"), (prio or autos)[0]))
        if self.has("exposure_dynamic"):
            c = self.ctrls[self.has("exposure_dynamic")]
            out.append((self.has("exposure_dynamic"), c.get("default", 0)))
        if self.has("wb_auto"):
            out.append((self.has("wb_auto"), 1))
        return out

    def power_line(self):
        if self.has("power_line"):
            v = self.ctl.get(self.has("power_line"))
            if v:                               # 0 = disabled: leave it to the camera
                self.keep("power_line", v)

    def apply(self, settings):
        self.touched = True
        for name, value in settings:
            self.ctl.set(name, value)
        time.sleep(SETTLE_S)


def choose_focus(rows):
    """Sharpest card, but among the near-sharpest (>= 80% of the peak) the one
    whose aiming-mark edge fits best: the C920's peak was 30-35 by sharpness,
    30 by edge fit (0.075 vs 0.105 px)."""
    found = [r for r in rows if r["found"] and r["sharp"] is not None]
    if not found:
        return None
    top = max(r["sharp"] for r in found)
    near = [r for r in found if r["sharp"] >= 0.8 * top]
    with_edge = [r for r in near if r["edge"] is not None]
    if with_edge:
        return min(with_edge, key=lambda r: r["edge"])["value"]
    return max(near, key=lambda r: r["sharp"])["value"]


def describe(m):
    if not m["found"]:
        return f"card NOT found  sharp {m['sharp']:7.1f}  paper {m['paper']:5.0f}"
    e = f"{m['edge']:.3f}" if m["edge"] is not None else "  -  "
    r = f"{m['ring']:.3f}" if m["ring"] is not None else "  -  "
    return (f"sharp {m['sharp']:7.1f}  edge {e} px  rings {r} mm  "
            f"paper {m['paper']:5.0f}  black {m['black']:4.0f}  clipped {m['sat']:.2f}%")


def stream_fps(device):
    """ustreamer's frame rate (its /state), else 10."""
    if isinstance(device, str) and device.startswith("http"):
        base = device.rsplit("/stream", 1)[0]
        try:
            with urllib.request.urlopen(base + "/state", timeout=5) as r:
                return float(json.load(r)["result"]["source"]["desired_fps"]) or 10.0
        except Exception:
            pass
    return 10.0


def write_profile(path, ident, settings, notes):
    vid, pid, name = ident
    lines = [f"# {name} ({vid}:{pid}) - spotter camera settings, by engine/camtune.py",
             *(f"# {n}" for n in notes),
             "# One control=value per line, applied IN ORDER, one per v4l2-ctl call",
             "# (an auto switch comes before the manual value it guards).",
             *(f"{n}={v}" for n, v in settings)]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n")


# ---------------------------------------------------------------- main

def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0],
                                formatter_class=argparse.RawDescriptionHelpFormatter,
                                epilog=__doc__.split("\n\n", 1)[1])
    where = p.add_mutually_exclusive_group(required=True)
    where.add_argument("--pi", metavar="[USER@]HOST",
                       help="the camera is on the Pi (e.g. spotter.local): controls "
                            "over ssh, pictures from its stream")
    where.add_argument("--local", metavar="/dev/videoN",
                       help="the camera is on THIS machine (Linux)")
    p.add_argument("--device", type=target0.parse_device, default=None,
                   help="where the pictures come from (default: the Pi's "
                        "http://HOST:8080/stream, or index 0 with --local)")
    p.add_argument("--video", default="/dev/video0",
                   help="the camera's device on the Pi (default /dev/video0)")
    p.add_argument("--target", choices=sorted(SPECS), default="pistol")
    p.add_argument("--quick", action="store_true",
                   help="fewer points and frames (~2 min instead of ~6)")
    p.add_argument("--no-install", dest="install", action="store_false",
                   help="write the profile in the repo only, not on the Pi")
    a = p.parse_args()
    sys.stdout.reconfigure(line_buffering=True)
    phase1._stop_signals()      # Ctrl+C / kill -> KeyboardInterrupt -> camera put back

    if a.local:
        if sys.platform == "darwin":
            sys.exit("A camera on a Mac cannot be tuned: macOS has no way to set a "
                     "webcam's focus / exposure from code. Plug it into the Pi and "
                     "use --pi.")
        ctl, video, device = Controls(None), a.local, a.device if a.device is not None else 0
        ctl.video = video
    else:
        host = a.pi.split("@")[-1]
        ctl = Controls(a.pi, a.video)
        device = a.device or f"http://{host}:8080/stream"
        try:
            ctl.run("command -v v4l2-ctl")
        except Exception as e:
            sys.exit(f"Can't run v4l2-ctl on {a.pi}: {e}\n"
                     f"  ssh needs a key, not a password - once, from here:  ssh-copy-id {a.pi}\n"
                     "  and the Pi needs v4l-utils - pi/install.sh sets it up")
    spec = SPECS[a.target]
    try:
        ident = ctl.identity()
    except Exception:
        ident = ("0000", "0000", "camera")
    print(f"\n  camera: {ident[2]} ({ident[0]}:{ident[1]}) at {a.pi or 'this machine'}"
          f"\n  pictures from {device}")

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    out = phase1.OUT / "camtune" / stamp
    out.mkdir(parents=True, exist_ok=True)

    rig = Rig(device, spec)
    tuner = Tuner(ctl, rig, quick=a.quick)
    start = {n: c["value"] for n, c in tuner.ctrls.items() if "value" in c}
    done = False
    try:
        g = rig.frame()
        err = rig.masks(g)
        if err:
            sys.exit(f"  no target in view ({err}).\n  Put a CLEAN {a.target} card "
                     "on the trap, check the camera sees all of it, and run again.")
        cv2.imwrite(str(out / "as_found.jpg"), np.clip(g, 0, 255).astype(np.uint8))
        found = rig.measure(3)
        print("  as found: " + describe(found))
        missing = [r for r in ("focus", "exposure", "gain", "wb") if not tuner.has(r)]
        if missing:
            print(f"  (this camera has no control for: {', '.join(missing)})")
        print("  Don't touch the camera or the card until it's done.\n")

        def still_there(step):
            m = rig.measure(2)
            if not m["found"]:
                raise Lost(f"the card went out of sight after the {step} "
                           f"(paper reads {m['paper']:.0f}) - did the light change?")
            return m

        tuner.focus()
        still_there("focus sweep")
        tuner.exposure(stream_fps(device))
        still_there("exposure sweep")
        tuner.white_balance()
        tuner.power_line()

        # tuned vs the camera's own automatics, as `bench` measures them
        rounds = 8 if a.quick else 15
        print(f"\n  bench: tuned vs automatic, {rounds} frames each")
        tuned_set = list(tuner.chosen)
        tuner.apply(tuned_set)
        tuned = rig.bench(rounds)
        tuned_m = rig.measure(3)
        auto_set = tuner.automatics()
        tuner.apply(auto_set)
        time.sleep(3.0)                          # autofocus / AE hunting
        auto = rig.bench(rounds)
        auto_m = rig.measure(3)
        budget = decimal_step_mm(spec) / 4.0

        def passes(b):
            return b is not None and b["phantoms_max"] == 0 and b["geom_worst_mm"] < budget / 4

        use_auto = not passes(tuned) and passes(auto)
        final = auto_set if use_auto else tuned_set
        if tuned is None or (use_auto and auto is None):
            raise Lost("the card went out of sight during the bench - did the light change?")
        tuner.apply(final)
        done = True
    except Lost as e:
        print(f"\n  STOPPED: {e}\n  No profile written. Fix it and run again.")
        (out / "camtune.json").write_text(json.dumps(
            {"stopped": str(e), "as_found": locals().get("found"),
             "sweeps": tuner.steps}, indent=1, default=str))
        print(f"  log so far -> {out}/camtune.json")
    finally:
        if not done and tuner.touched:
            print("\n  stopped: putting the camera back as it was")
            try:
                order = sorted(start.items(), key=lambda kv: any(
                    kv[0] in NAMES[r] for r in ("focus_auto", "exposure_auto", "wb_auto")))
                known = {x for r in NAMES.values() for x in r}
                for n, v in order:
                    if n in known:
                        try:
                            ctl.set(n, v)
                        except Exception:
                            pass
            except Exception as e:
                print(f"  (could not restore everything: {e})")
        rig.close()
    if not done:
        sys.exit(1)

    def row(label, m, b):
        if b is None:
            return f"  {label:<10} card not found in enough frames"
        return (f"  {label:<10}{m['sharp']:>9.1f}{b['edge_rms_px']:>9.2f}{b['ring_rms_mm']:>9.3f}"
                f"{b['geom_noise_mm']:>10.4f}{b['geom_worst_mm']:>10.4f}{b['phantoms_max']:>9}"
                f"{b['contrast']:>9}{b['sat_pct']:>7.2f}")
    print(f"\n  {'':<10}{'sharp':>9}{'edge px':>9}{'ring mm':>9}{'geom mm':>10}"
          f"{'worst mm':>10}{'phantom':>9}{'contrast':>9}{'sat%':>7}")
    print(row("automatic", auto_m, auto))
    print(row("tuned", tuned_m, tuned))
    print(f"  budget {budget:.2f} mm")

    vid, pid, name = ident
    if use_auto:
        print("\n  The camera's automatics did better here: no profile written, "
              "it stays on auto.")
    else:
        b = tuned
        ae = auto["edge_rms_px"] if auto else "-"
        notes = [f"tuned {datetime.now():%Y-%m-%d} on the rig ({a.target} card), against the "
                 "camera's automatics:",
                 f"  sharpness {auto_m['sharp']:.0f} -> {tuned_m['sharp']:.0f}, edge fit {ae} -> "
                 f"{b['edge_rms_px']} px, rings {b['ring_rms_mm']} mm, geometry noise "
                 f"{b['geom_noise_mm']} mm, contrast {b['contrast']}",
                 "Focus depends on the camera-to-card distance, exposure on the light:",
                 "re-run camtune.py after moving the camera or changing the lighting."]
        path = PROFILES / f"{vid}-{pid}.conf"
        write_profile(path, ident, final, notes)
        print(f"\n  profile -> {path.relative_to(ROOT)}  (commit it to share it)")
        for n, v in final:
            print(f"    {n}={v}")
        if a.pi and a.install:
            try:
                ctl.run(f"test -w {PI_PROFILES}")
                with open(path) as f:
                    subprocess.run(ctl.ssh + [f"cat > {PI_PROFILES}/{vid}-{pid}.conf"],
                                   stdin=f, check=True, timeout=30)
                print(f"  installed on {a.pi}: {PI_PROFILES}/{vid}-{pid}.conf - applied "
                      "on every stream start and camera plug-in")
            except Exception:
                print(f"  NOT installed on the Pi: {PI_PROFILES} is missing - run "
                      "pi/install.sh there first (the settings are live until the "
                      "camera is replugged)")

    report = {"camera": {"vendor": vid, "product": pid, "name": name},
              "device": str(device), "target": a.target, "as_found": found,
              "sweeps": tuner.steps, "tuned": {"settings": tuned_set, "measure": tuned_m,
                                               "bench": tuned},
              "automatic": {"settings": auto_set, "measure": auto_m, "bench": auto},
              "kept": "automatic" if use_auto else "tuned"}
    (out / "camtune.json").write_text(json.dumps(report, indent=1, default=str))
    print(f"  full log -> {out}/camtune.json\n")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
