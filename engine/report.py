#!/usr/bin/env python3
"""
Report the engine's events to the web app (web/). Contract: docs/engine-events.md.

    rep = Reporter("http://localhost:3000", target="pistol", rule="pellet")
    rep.send("ready")
    rep.send("shot", {...}, files={"after_image": ("after.png", png_bytes, "image/png")})
    # a file may also be a callable returning that tuple: run on the reporter thread
    rep.close()

Posts from a background thread through a bounded queue, so the web app being
slow, restarting or absent NEVER slows or stops scoring: failures are logged and
the event is dropped. The shot log and frames on disk stay the record.

Standard library only (urllib + a small multipart encoder): no new dependency
for the engine.
"""
import json
import queue
import threading
import time
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timezone

import cv2
import numpy as np


def _iso(ts):
    return datetime.fromtimestamp(ts, timezone.utc).isoformat(timespec="milliseconds")


def _multipart(fields, files):
    """(body bytes, content-type) for a multipart/form-data POST."""
    boundary = uuid.uuid4().hex
    out = []
    for name, value in fields.items():
        out += [f"--{boundary}\r\n".encode(),
                f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode(),
                value.encode() if isinstance(value, str) else value, b"\r\n"]
    for name, (filename, data, ctype) in files.items():
        out += [f"--{boundary}\r\n".encode(),
                (f'Content-Disposition: form-data; name="{name}"; '
                 f'filename="{filename}"\r\nContent-Type: {ctype}\r\n\r\n').encode(),
                data, b"\r\n"]
    out.append(f"--{boundary}--\r\n".encode())
    return b"".join(out), f"multipart/form-data; boundary={boundary}"


def png(img):
    ok, buf = cv2.imencode(".png", np.clip(img, 0, 255).astype(np.uint8))
    return buf.tobytes() if ok else b""


def jpeg(img, quality=90):
    ok, buf = cv2.imencode(".jpg", np.clip(img, 0, 255).astype(np.uint8),
                           [cv2.IMWRITE_JPEG_QUALITY, quality])
    return buf.tobytes() if ok else b""


def closeup(img, tf, centre_mm, size_px=480, px_per_mm=20.0):
    """
    A straightened, top-down close-up of the target around centre_mm: perspective
    and lens distortion removed through the frame's own geometry, at a fixed
    px_per_mm, so a pixel maps straight to target millimetres (y up). These are
    what the review page draws on and taps, and a uniform patch for the planned
    model to train on.
    """
    cx, cy = centre_mm
    v, u = np.mgrid[0:size_px, 0:size_px].astype(np.float64)
    x = cx + (u - size_px / 2.0) / px_per_mm
    y = cy - (v - size_px / 2.0) / px_per_mm
    sx, sy = tf.from_mm(x, y)
    return cv2.remap(np.asarray(img, np.float32), sx.astype(np.float32),
                     sy.astype(np.float32), cv2.INTER_LINEAR,
                     borderMode=cv2.BORDER_CONSTANT, borderValue=0)


class Reporter:
    def __init__(self, base_url, target="pistol", rule="pellet", token=None,
                 timeout=5.0, session_id=None):
        self.url = base_url.rstrip("/") + "/api/events"
        # The web app creates the session and passes its id (and token) when it
        # starts the engine; a run started by hand makes its own.
        self.session_id = session_id or (time.strftime("%Y%m%d-%H%M%S") + "-"
                                         + uuid.uuid4().hex[:4])
        self.target, self.rule, self.token, self.timeout = target, rule, token, timeout
        # TWO LANES (2026-11-12): events with pictures (a shot's frames, an
        # unscored capture) take seconds to encode and upload; in one queue the
        # announcements and scores waited behind them, and with false triggers
        # piling pictures up the announcer fell further behind every shot. Now
        # everything without pictures goes at once in its own lane.
        self.q = queue.Queue(maxsize=200)        # pictures, in order
        self.fast = queue.Queue(maxsize=500)     # everything else, at once
        self.failures = 0
        self._th = threading.Thread(target=self._run, args=(self.q,), daemon=True)
        self._fast_th = threading.Thread(target=self._run, args=(self.fast,), daemon=True)
        self._th.start()
        self._fast_th.start()

    def send(self, type_, data=None, files=None, at=None):
        payload = {"type": type_, "session_id": self.session_id,
                   "at": _iso(at if at is not None else time.time()),
                   "data": data or {}}
        try:
            (self.q if files else self.fast).put_nowait((payload, files or {}))
        except queue.Full:
            print("  [report] queue full - event dropped", flush=True)

    def close(self, wait=8.0):
        """Give queued events a moment to go out (e.g. session_ended), and the
        pictures still queued a little longer."""
        self.fast.put((None, None))
        self.q.put((None, None))
        self._fast_th.join(timeout=wait)
        self._th.join(timeout=wait + 12.0)

    def _run(self, q):
        while True:
            payload, files = q.get()
            if payload is None:
                return
            try:
                # files may be deferred (callables) so image encoding and close-up
                # warps happen here, off the scoring thread
                files = {k: (v() if callable(v) else v) for k, v in files.items()}
                files = {k: v for k, v in files.items() if v and v[1]}
            except Exception as e:                       # never kill the thread
                print(f"  [report] could not prepare images: {e}", flush=True)
                files = {}
            body, ctype = _multipart({"event": json.dumps(payload)}, files)
            req = urllib.request.Request(self.url, data=body, method="POST",
                                         headers={"Content-Type": ctype})
            if self.token:
                req.add_header("Authorization", f"Bearer {self.token}")
            try:
                with urllib.request.urlopen(req, timeout=self.timeout) as r:
                    r.read()
                self.failures = 0
            except (urllib.error.URLError, OSError, ValueError) as e:
                self.failures += 1
                if self.failures in (1, 10) or self.failures % 50 == 0:
                    print(f"  [report] could not reach {self.url}: {e} "
                          f"({self.failures} failed)", flush=True)
