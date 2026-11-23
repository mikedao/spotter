# The Pi at the target

A Raspberry Pi 3 (hostname `spotter`) next to the target streams the camera to
the laptop; the laptop runs the engine and the web app. Set up 2026-11-12 with
the Razer Kiyo; since 2026-11-23 (the Kiyo broke) a **Logitech C920** (046d:082d).

## Setup (Raspberry Pi OS)

```bash
sudo apt update && sudo apt install -y ustreamer v4l-utils
v4l2-ctl --list-devices          # the camera: /dev/video0 (video1 is metadata)
sed "s/YOUR_USER/$USER/" spotter-camera.service | sudo tee /etc/systemd/system/spotter-camera.service
sudo install -m 755 camera-controls.sh /usr/local/bin/spotter-camera-controls
sudo cp spotter-camera-controls.service /etc/systemd/system/
sudo cp 99-spotter-camera.rules /etc/udev/rules.d/ && sudo udevadm control --reload
sudo systemctl daemon-reload && sudo systemctl enable --now spotter-camera
```

It starts on boot and restarts if the stream stops. The camera's settings live
in `camera-controls.sh`, applied after the stream starts AND on every plug-in
(the udev rule): a C920 forgets its settings without power, and ustreamer reopens
a replugged camera by itself, so settings applied only at service start were lost
(found 2026-11-23: the C920 came up on autofocus). A different camera needs its
own ids in the rule and its own sweep below.

## Using it

- In the app's camera step: `http://spotter.local:8080/stream`
  (`spotter.local` resolves on the home network; else the Pi's IP, `hostname -I`).
- ustreamer's own page: `http://spotter.local:8080/`, state as JSON at `/state`.
- `systemctl status spotter-camera` / `journalctl -u spotter-camera` on the Pi.

## Logitech C920 settings (swept 2026-11-23 on the rig, ~30 deg, pistol card)

Scored with `phase1.py locate` / `bench` per setting:

| setting | value | why |
|---|---|---|
| focus | MANUAL 30 (0-250, steps of 5) | autofocus: sharpness 16, edge 0.30 px, rings 0.117 mm. 30: sharpness ~100-118, edge 0.06-0.075 px, rings 0.075. 35 as sharp, edge 0.105; 25 and 40 half as sharp; rings lost beyond ~60. RE-SWEEP if the distance changes |
| exposure | MANUAL 666 (66.7 ms), dynamic framerate OFF | unlike the Kiyo, manual exposure WORKS: brightness follows it, no clipping anywhere 50-1000; sharpness peaks 666-800 |
| gain | 40 | bench, 15 frames: 666/g40 geom noise 0.0026 mm, contrast 153; 666/g0 0.0048, 117; 800/g0 0.0084, 126; auto (gain 86) 0.0038, 141. All far inside 0.2 mm - picked for contrast and no auto-exposure hunting between a shot's before and after |
| white balance | MANUAL 4970 K | what auto had settled on; locked so it can't drift |
| format | MJPEG 1920x1080 (up to 30 fps), stream 10 fps | 2304x1296 is 2 fps only |

Manual exposure means a LIGHTING change (garage door open, lights) is not
followed: re-run the camera check, and re-sweep exposure if the light changes for good.

## Measured with the Kiyo (2026-11-12, home Wi-Fi)

The Kiyo offered 1920x1080 MJPEG at 30 fps only; `--desired-fps=10` gives
7-8 fps captured, ~22.5 Mbit/s, ~370 KB a frame. Enough: the engine needs a
fresh frame about once a second.

## Kiyo focus (locked, 2026-11-12; the sweep method still applies)

Swept `focus_absolute` 0-255 in 5s, then 178-192 in 1s, scoring each frame with
`phase1.py locate` (sharpness = Laplacian variance, plus the ring fit). A sharp,
narrow peak: 187 = sharpness 629, rings 0.073 mm (auto focus: 466); half that 10
steps either side, rings lost beyond 170-205. RE-SWEEP if the camera-to-card
distance changes (the C920 steps focus in 5s):

```bash
v4l2-ctl -d /dev/video0 -c focus_automatic_continuous=0
for v in $(seq 0 5 255); do v4l2-ctl -d /dev/video0 -c focus_absolute=$v; sleep 2.5
  curl -s -o f_$(printf %03d $v).jpg http://localhost:8080/snapshot; done
python3 -m http.server 8090     # the laptop scores them with `phase1.py locate --json`
```

## Kiyo exposure, white balance, sharpening: were left ON AUTO (tested 2026-11-12)

A sweep of manual exposure 21-125 (gain 0, WB locked 3950) x sharpness 0/64/128/192,
6 frames each, scored with the engine, against the auto settings:

- Manual exposure is broken on the Kiyo: every value 21-125 gave the SAME frame,
  far too bright - 78% of the paper clipped white (auto: 0%), the black lifted
  to 74 (auto: 0), ring fit 0.092-0.101 mm (auto 0.074), scale jitter 3-15 um
  (auto 2.2-2.5). Auto exposure is steady (no drift over the sweep, no flicker).
- Sharpness has two effective levels (0=64, 128=192); below 128 the ring fit
  worsens. Keep the default 128.
- Set controls ONE PER v4l2-ctl CALL: several `-c` in one call left the Kiyo
  sending black frames (the first sweep: all 168 manual frames black).
- With focus locked at 187 and the rest on auto, frame-to-frame jitter of the
  fitted target is ~1 um (centre) / ~2-3 um (scale) against a 200 um budget.

## Not done yet

- The camera's microphone is unused (ustreamer is video only): use the laptop's mic
  at the firing line, which hears the gun.
