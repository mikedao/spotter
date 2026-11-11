import signal, sys
import cv2, numpy as np

def bail(*_):
    print("TIMEOUT - camera did not respond in 15s.")
    print("Most likely the terminal app lacks camera permission.")
    sys.exit(2)

signal.signal(signal.SIGALRM, bail)
signal.alarm(15)

cap = cv2.VideoCapture(0)
if not cap.isOpened():
    print("RESULT: no camera opened at index 0")
    sys.exit(1)
for req in ((1920, 1080), (1280, 720)):
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, req[0])
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, req[1])
    for _ in range(5):
        cap.read()
    ok, f = cap.read()
    if ok and f is not None:
        g = cv2.cvtColor(f, cv2.COLOR_BGR2GRAY)
        print(f"  requested {req[0]}x{req[1]} -> got {f.shape[1]}x{f.shape[0]}  "
              f"mean {g.mean():.1f}  focus {cv2.Laplacian(g, cv2.CV_64F).var():.1f}")
    else:
        print(f"  requested {req[0]}x{req[1]} -> read failed")
print(f"  autofocus prop={cap.get(cv2.CAP_PROP_AUTOFOCUS)}  "
      f"backend={cap.getBackendName()}")
cap.release()
print("RESULT: camera OK")
