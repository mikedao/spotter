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

## Not done yet

- **Lock focus, exposure and white balance** (`v4l2-ctl -d /dev/video0 -c ...`),
  once the card is in view: `focus_automatic_continuous=0` + `focus_absolute`,
  `auto_exposure=1` (manual) + `exposure_time_absolute`, `exposure_dynamic_framerate=0`,
  `white_balance_automatic=0` + `white_balance_temperature`. Then add them to the
  service as `ExecStartPre=` lines, since they reset when the camera powers up.
- The Kiyo's microphone is unused (ustreamer is video only): use the laptop's mic
  at the firing line, which hears the gun.
