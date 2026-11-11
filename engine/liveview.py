"""
The engine's camera as a live picture for the web app's range screen.

During a session the engine holds the camera (only one process can), so the
web app cannot open it; the engine serves it instead, from the frames it is
already reading: small, a few frames a second, with the rings fitted at the
last baseline drawn on - so a glance shows the card is still in view and the
fit still sits on it.

    view = LiveView(cam, spec, geometry=lambda: st.get("tf_b"))
    srv = view.serve(port)            # 127.0.0.1 only; the web app relays it
    ...
    srv.shutdown()

GET /snapshot.jpg = the latest picture; GET /stream = MJPEG.
Pictures are encoded only when asked for, so nobody watching costs nothing.
"""
import threading
import time

import cv2
import numpy as np

from camstream import Server, make_handler

RING_BGR = (0, 200, 255)
LOST_BGR = (40, 40, 220)


class LiveView:
    def __init__(self, cam, spec, geometry=lambda: None, width=960, quality=70, fps=4.0):
        self.cam, self.spec, self.geometry = cam, spec, geometry
        self.width, self.quality, self.gap = width, quality, 1.0 / fps
        self.lock = threading.Lock()
        self.jpeg, self.made_at, self.seq = None, 0.0, 0
        self._rings_for, self._rings = None, []

    def _ring_lines(self, tf, k):
        """Ring outlines in the small picture's pixels, recomputed only when the
        geometry changes (each new baseline)."""
        key = (id(tf), k)
        if tf is None:
            return []
        if self._rings_for != key:
            from scoring import ring_radius_mm
            small = tf.scaled(k)
            a = np.linspace(0, 2 * np.pi, 180, endpoint=False)
            lines = []
            for ring in range(10, 0, -1):
                rr = ring_radius_mm(self.spec, ring)
                x, y = small.from_mm(rr * np.cos(a), rr * np.sin(a))
                lines.append(np.round(np.stack([x, y], 1) * 16).astype(np.int32))
            self._rings_for, self._rings = key, lines
        return self._rings

    def latest_jpeg(self):
        with self.lock:
            if self.jpeg is not None and time.time() - self.made_at < self.gap:
                return self.jpeg
            with self.cam.lock:
                frame = self.cam.frame
            if frame is None:
                return self.jpeg
            k = min(1.0, self.width / frame.shape[1])
            small = cv2.resize(frame, None, fx=k, fy=k, interpolation=cv2.INTER_AREA) \
                if k < 1.0 else frame.copy()
            lines = self._ring_lines(self.geometry(), k)
            if lines:
                cv2.polylines(small, lines, True, RING_BGR, 1, cv2.LINE_AA, shift=4)
            if self.cam.lost:
                cv2.putText(small, "camera connection lost", (16, 40),
                            cv2.FONT_HERSHEY_SIMPLEX, 1.0, LOST_BGR, 2, cv2.LINE_AA)
            ok, buf = cv2.imencode(".jpg", small, [cv2.IMWRITE_JPEG_QUALITY, self.quality])
            if ok:
                self.jpeg, self.made_at, self.seq = buf.tobytes(), time.time(), self.seq + 1
            return self.jpeg

    def next_jpeg(self, after_seq):
        """For the MJPEG stream: the next picture after `after_seq`."""
        time.sleep(self.gap)
        jpeg = self.latest_jpeg()
        return jpeg, self.seq

    def serve(self, port, host="127.0.0.1"):
        srv = Server((host, port), make_handler(self, 1.0 / self.gap))
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        return srv
