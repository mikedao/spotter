#!/usr/bin/env python3
"""
The camera's microphone as a SHOT TRIGGER - not as a position sensor.

Acoustic positioning was rejected (see CLAUDE.md): it needs sub-microsecond
timing. A trigger only has to say "a shot just happened, take the after
photo", so tens of milliseconds of latency are irrelevant, and a false
trigger is harmless because vision confirms whether a new hole appeared.

This module finds the microphone, follows the loudness envelope, and reports
impulsive events (sharp, loud, short) against a running noise floor.
"""
import math
import queue
import time
from collections import deque

import numpy as np

ENV_MS = 2.0            # envelope resolution
MERGE_MS = 25.0         # sub-events closer than this are one event
FLOOR_S = 3.0           # running noise-floor window


def find_input(name="Kiyo"):
    """Index and info of the first input device whose name contains `name`."""
    import sounddevice as sd
    for i, d in enumerate(sd.query_devices()):
        if d["max_input_channels"] > 0 and name.lower() in d["name"].lower():
            return i, d
    names = [d["name"] for d in sd.query_devices() if d["max_input_channels"] > 0]
    raise SystemExit(f"no input device matching '{name}'. Inputs: {names}")


def dbfs(x):
    return 20.0 * math.log10(max(float(x), 1e-9))


class EventDetector:
    """
    Feed audio blocks; get impulsive events back.

    The envelope is the peak |sample| per ENV_MS window. The floor is the
    median envelope over the last FLOOR_S seconds of NON-event audio, so a
    noisy room raises the bar automatically. An event starts when the envelope
    exceeds floor * ratio and ends after MERGE_MS below it.
    """

    def __init__(self, rate, ratio_db=20.0):
        self.rate = rate
        self.win = max(1, int(rate * ENV_MS / 1000.0))
        self.ratio = 10 ** (ratio_db / 20.0)
        self.hist = deque(maxlen=int(FLOOR_S * 1000.0 / ENV_MS))
        self.buf = np.zeros(0, np.float32)
        self.t = 0.0                      # seconds of audio consumed
        self.cur = None                   # event in progress
        self.quiet_ms = 0.0

    @property
    def floor(self):
        if len(self.hist) < int(500.0 / ENV_MS):   # 0.5 s of floor first
            return None
        return max(float(np.median(self.hist)), 1e-5)

    def feed(self, block):
        """Process a mono float block; return a list of finished events."""
        self.buf = np.concatenate([self.buf, block])
        n = len(self.buf) // self.win
        if n == 0:
            return []
        env = np.abs(self.buf[: n * self.win]).reshape(n, self.win).max(axis=1)
        self.buf = self.buf[n * self.win:]
        done = []
        for v in env:
            fl = self.floor
            hot = fl is not None and v > fl * self.ratio
            if hot:
                if self.cur is None:
                    self.cur = {"t": self.t, "peak": v, "floor": fl,
                                "above_ms": 0.0}
                self.cur["peak"] = max(self.cur["peak"], v)
                self.cur["above_ms"] += ENV_MS
                self.quiet_ms = 0.0
            else:
                self.hist.append(v)
                if self.cur is not None:
                    self.quiet_ms += ENV_MS
                    if self.quiet_ms >= MERGE_MS:
                        e = self.cur
                        e["len_ms"] = (self.t - e["t"]) * 1000.0 - self.quiet_ms
                        e["peak_db"] = dbfs(e["peak"])
                        e["over_db"] = dbfs(e["peak"]) - dbfs(e["floor"])
                        done.append(e)
                        self.cur = None
            self.t += ENV_MS / 1000.0
        return done


def listen(seconds=60.0, name="Kiyo", ratio_db=20.0, on_event=None,
           wav_path=None):
    """
    Stream the microphone for `seconds` (Ctrl+C stops early), printing each
    impulsive event. Returns (events, floor_dbfs, samples, rate).
    """
    import sounddevice as sd
    idx, info = find_input(name)
    rate = int(info["default_samplerate"])
    ch = min(2, int(info["max_input_channels"]))
    q = queue.Queue()

    def cb(indata, frames, t, status):
        q.put(indata.mean(axis=1).astype(np.float32).copy())

    det = EventDetector(rate, ratio_db)
    events, chunks = [], []
    t0 = time.time()
    with sd.InputStream(device=idx, channels=ch, samplerate=rate,
                        blocksize=int(rate * 0.05), callback=cb):
        try:
            while time.time() - t0 < seconds:
                try:
                    blk = q.get(timeout=1.0)
                except queue.Empty:
                    continue
                chunks.append(blk)
                for e in det.feed(blk):
                    events.append(e)
                    if on_event:
                        on_event(e, events)
        except KeyboardInterrupt:
            pass
    x = np.concatenate(chunks) if chunks else np.zeros(0, np.float32)
    if wav_path is not None and len(x):
        import wave
        with wave.open(str(wav_path), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(rate)
            w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())
    fl = det.floor
    return events, (dbfs(fl) if fl else None), x, rate
