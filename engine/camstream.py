#!/usr/bin/env python3
"""
Serve a camera as an MJPEG stream, the way the Raspberry Pi at the target will.

    ./.venv/bin/python camstream.py --device 0 --port 8080
    # then: phase1.py shot --auto --device http://localhost:8080/stream

On the Pi itself use `ustreamer` instead (see ../pi/): it forwards the Kiyo's own
MJPEG frames without decoding them, which a Pi 3 can do all day. This script
decodes and re-encodes, so it is for testing streaming on the laptop - the same
path the engine will see, without a Pi.

Standard library + OpenCV; serves the latest frame to every client.
"""
import argparse
import socketserver
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import cv2

BOUNDARY = "spotterframe"


class Camera:
    """Reads continuously; keeps only the latest JPEG. With `image`, serves that
    still picture as if it were a live camera; with `playlist`, a series of
    pictures in turn, `every` seconds apart, holding the last - e.g. a card
    photographed after each shot, replayed as if shot live (tests and demos)."""

    def __init__(self, device, width, height, quality, image=None, playlist=None, every=8.0):
        self.playlist = []
        for path in playlist or []:
            img = cv2.imread(path)
            if img is None:
                raise SystemExit(f"could not read {path}")
            self.playlist.append(img)
        self.every, self.t0 = every, time.time()
        if self.playlist:
            image = None
        self.still = cv2.imread(image) if image else (self.playlist[0] if self.playlist else None)
        if image and self.still is None:
            raise SystemExit(f"could not read {image}")
        if self.still is None:
            self.cap = cv2.VideoCapture(device)
            if not self.cap.isOpened():
                raise SystemExit(f"could not open camera {device} (camera permission?)")
            self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, width)
            self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height)
        self.quality = quality
        self.jpeg, self.seq = None, 0
        self.cond = threading.Condition()
        threading.Thread(target=self._run, daemon=True).start()

    def _run(self):
        while True:
            if self.playlist:
                i = min(int((time.time() - self.t0) / self.every), len(self.playlist) - 1)
                ok, frame = True, self.playlist[i]
                time.sleep(1 / 30)
            elif self.still is not None:
                ok, frame = True, self.still
                time.sleep(1 / 30)
            else:
                ok, frame = self.cap.read()
            if not ok:
                time.sleep(0.05)
                continue
            ok, buf = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, self.quality])
            if ok:
                with self.cond:
                    self.jpeg, self.seq = buf.tobytes(), self.seq + 1
                    self.cond.notify_all()

    def latest_jpeg(self):
        with self.cond:
            return self.jpeg

    def next_jpeg(self, after_seq):
        with self.cond:
            self.cond.wait_for(lambda: self.seq > after_seq, timeout=5.0)
            return self.jpeg, self.seq


class Server(ThreadingHTTPServer):
    """HTTPServer.server_bind looks up this machine's fully qualified name,
    which can hang for a long time on macOS (and on a Pi with no DNS at the
    range). We never use the name, so skip the lookup."""
    daemon_threads = True

    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        self.server_name, self.server_port = "spotter", self.server_address[1]


def make_handler(cam, fps):
    """GET /stream (or /) = MJPEG; GET /snapshot.jpg = the latest picture.
    `cam` needs next_jpeg(after_seq) -> (jpeg, seq) and latest_jpeg()."""
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_GET(self):
            if self.path == "/snapshot.jpg":
                jpeg = cam.latest_jpeg()
                if jpeg is None:
                    self.send_error(503, "no picture yet")
                    return
                self.send_response(200)
                self.send_header("Content-Type", "image/jpeg")
                self.send_header("Content-Length", str(len(jpeg)))
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                self.wfile.write(jpeg)
                return
            if self.path not in ("/stream", "/"):
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Type", f"multipart/x-mixed-replace; boundary={BOUNDARY}")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            seq, gap = 0, 1.0 / fps
            try:
                while True:
                    t0 = time.time()
                    jpeg, seq = cam.next_jpeg(seq)
                    if jpeg is None:
                        continue
                    self.wfile.write(
                        f"--{BOUNDARY}\r\nContent-Type: image/jpeg\r\n"
                        f"Content-Length: {len(jpeg)}\r\n\r\n".encode() + jpeg + b"\r\n")
                    time.sleep(max(0.0, gap - (time.time() - t0)))
            except (BrokenPipeError, ConnectionResetError):
                pass

    return Handler


def main():
    p = argparse.ArgumentParser(description="Serve a camera as MJPEG")
    p.add_argument("--device", type=int, default=0)
    p.add_argument("--port", type=int, default=8080)
    p.add_argument("--width", type=int, default=1920)
    p.add_argument("--height", type=int, default=1080)
    p.add_argument("--fps", type=float, default=15.0)
    p.add_argument("--quality", type=int, default=95)
    p.add_argument("--image", default=None,
                   help="serve this still image instead of a camera (testing, demos)")
    p.add_argument("--playlist", nargs="+", default=None,
                   help="serve these images in turn, --every seconds apart (replay a card)")
    p.add_argument("--every", type=float, default=8.0)
    a = p.parse_args()
    cam = Camera(a.device, a.width, a.height, a.quality, a.image, a.playlist, a.every)
    srv = Server(("0.0.0.0", a.port), make_handler(cam, a.fps))
    what = (f"{len(a.playlist)} images, {a.every:g} s apart" if a.playlist
            else a.image or f"camera {a.device}")
    print(f"streaming {what} at http://<this machine>:{a.port}/stream "
          f"({a.fps:g} fps, JPEG quality {a.quality}). Ctrl+C to stop.")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
