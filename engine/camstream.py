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
    """Reads continuously; keeps only the latest JPEG."""

    def __init__(self, device, width, height, quality):
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
            ok, frame = self.cap.read()
            if not ok:
                time.sleep(0.05)
                continue
            ok, buf = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, self.quality])
            if ok:
                with self.cond:
                    self.jpeg, self.seq = buf.tobytes(), self.seq + 1
                    self.cond.notify_all()

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
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_GET(self):
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
    a = p.parse_args()
    cam = Camera(a.device, a.width, a.height, a.quality)
    srv = Server(("0.0.0.0", a.port), make_handler(cam, a.fps))
    print(f"streaming camera {a.device} at http://<this machine>:{a.port}/stream "
          f"({a.fps:g} fps, JPEG quality {a.quality}). Ctrl+C to stop.")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
