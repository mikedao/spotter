# The Pi at the target

A Raspberry Pi 3 (hostname `spotter`) next to the target streams the Razer Kiyo
to the laptop; the laptop runs the engine and the web app. Set up 2026-11-12.

## Setup (Raspberry Pi OS)

```bash
sudo apt update && sudo apt install -y ustreamer v4l-utils
v4l2-ctl --list-devices          # the Kiyo: /dev/video0 (video1 is metadata)
sed "s/YOUR_USER/$USER/" spotter-camera.service | sudo tee /etc/systemd/system/spotter-camera.service
sudo systemctl daemon-reload && sudo systemctl enable --now spotter-camera
```

It starts on boot and restarts if the stream stops or the camera is replugged.

## Using it

- In the app's camera step: `http://spotter.local:8080/stream`
  (`spotter.local` resolves on the home network; else the Pi's IP, `hostname -I`).
- ustreamer's own page: `http://spotter.local:8080/`, state as JSON at `/state`.
- `systemctl status spotter-camera` / `journalctl -u spotter-camera` on the Pi.

## Measured (2026-11-12, home Wi-Fi)

The Kiyo offers 1920x1080 MJPEG at 30 fps only; `--desired-fps=10` gives
7-8 fps captured, ~22.5 Mbit/s, ~370 KB a frame. Enough: the engine needs a
fresh frame about once a second.

## Focus (locked, 2026-11-12)

Swept `focus_absolute` 0-255 in 5s, then 178-192 in 1s, scoring each frame with
`phase1.py locate` (sharpness = Laplacian variance, plus the ring fit). A sharp,
narrow peak: 187 = sharpness 629, rings 0.073 mm (auto focus: 466); half that 10
steps either side, rings lost beyond 170-205. The service sets it before every
start. RE-SWEEP if the camera-to-card distance changes:

```bash
v4l2-ctl -d /dev/video0 -c focus_automatic_continuous=0
for v in $(seq 0 5 255); do v4l2-ctl -d /dev/video0 -c focus_absolute=$v; sleep 2.5
  curl -s -o f_$(printf %03d $v).jpg http://localhost:8080/snapshot; done
python3 -m http.server 8090     # the laptop scores them with `phase1.py locate --json`
```

## Not done yet

- **Lock exposure and white balance** like the focus: `auto_exposure=1` (manual)
  + `exposure_time_absolute`, `exposure_dynamic_framerate=0`,
  `white_balance_automatic=0` + `white_balance_temperature`, as more
  `ExecStartPre=` lines (controls reset when the camera powers up).
- The Kiyo's microphone is unused (ustreamer is video only): use the laptop's mic
  at the firing line, which hears the gun.
