# The Pi at the target

A Raspberry Pi 3 (hostname `spotter`) next to the target streams the camera to
the laptop; the laptop runs the engine and the web app. Set up 2026-11-12 with
the Razer Kiyo; since 2026-11-23 (the Kiyo broke) a **Logitech C920** (046d:082d).

## Setup: any camera, three steps

1. **On the Pi** (Raspberry Pi OS), with this repo (or just its `pi/` folder) on it:

   ```bash
   cd pi && sudo ./install.sh
   ```

   Installs ustreamer + v4l-utils, the stream service (`spotter-camera`, on boot,
   restarts if it stops), the settings applier and its udev rule, and the known
   camera profiles. Safe to re-run after a `git pull`.

2. **From the laptop, once:** `ssh-copy-id USER@spotter.local` (camtune sets the
   camera's controls over ssh, no password prompts).

3. **A camera with no profile yet** (the Pi's log says "no settings for ..."): put
   a CLEAN card on the trap, lights as they will be for shooting, then from the laptop

   ```bash
   cd engine && ./.venv/bin/python camtune.py --pi USER@spotter.local   # ~6 min; --quick ~3
   ```

   It sweeps focus, exposure, gain and white balance, scoring every frame with
   the engine (sharpness, aiming-mark edge fit, ring fit, clipping), benches the
   result against the camera's own automatics, and writes
   `pi/cameras/<vendor>-<product>.conf` - installed on the Pi at once and applied
   from then on. Commit the profile so the next person with that camera starts
   from it. It stops and puts the camera back if the card goes out of sight
   (light switched off mid-run: 2026-11-23) or on Ctrl+C.

A camera already in `cameras/` works out of the box, but focus depends on the
camera-to-card DISTANCE and exposure on the LIGHT: re-run camtune after moving
the camera or changing the lighting. A camera on a Mac can't be tuned (macOS
offers no way to set a webcam's controls from code): plug it into the Pi.

**Why settings are applied on every plug-in:** a webcam like the C920 forgets
its settings without power, and ustreamer reopens a replugged camera by itself,
so settings applied only at service start were lost (2026-11-23: after swapping
the Kiyo for the C920 it came up on autofocus, sharpness 16 vs 118 tuned).
`spotter-camera-controls` (camera-controls.sh) runs after every stream start AND
on every USB camera plug-in, finds the camera's USB id and applies its profile
from `/etc/spotter/cameras/` (yours, so camtune writes it without sudo), one
control per `v4l2-ctl` call, in order. No profile = the camera's automatics.

## Using it

- In the app's camera step: `http://spotter.local:8080/stream`
  (`spotter.local` resolves on the home network; else the Pi's IP, `hostname -I`).
- ustreamer's own page: `http://spotter.local:8080/`, state as JSON at `/state`.
- On the Pi: `systemctl status spotter-camera`, `journalctl -u spotter-camera-controls`
  (which profile was applied), `v4l2-ctl -d /dev/video0 --list-ctrls` (the values now).

## Logitech C920 (046d:082d), 2026-11-23, rig ~30 deg, pistol card

Swept by hand first, then by camtune from the camera's automatics, which found
the same focus (30) on its own:

| setting | value | why |
|---|---|---|
| focus | MANUAL 30 (0-250, steps of 5) | autofocus: edge fit 0.26-0.30 px, rings 0.10-0.12 mm. 30: edge 0.06 px, rings 0.075. 35 as sharp, edge a little worse; 25 and 40 half as sharp; rings lost beyond ~60 |
| exposure | MANUAL 700 (70 ms; camtune caps at 70% of the 10 fps frame time), dynamic framerate OFF | unlike the Kiyo, manual exposure WORKS: brightness follows it, nothing clips anywhere 50-1000 |
| gain | 64 | paper 205 at 700/g64 (129 at gain 0); 96+ worsens the edge fit. Bench vs automatics: geometry noise 0.0031 vs 0.0060 mm, contrast 166 vs 139, 0 phantoms (by hand: 666/g40 0.0026 mm, contrast 153 - all far inside 0.2 mm) |
| white balance | MANUAL ~5000 K | what auto settles on; locked so it can't drift |
| format | MJPEG 1920x1080 (up to 30 fps), stream 10 fps | 2304x1296 is 2 fps only |

Manual exposure does not follow a LIGHTING change (garage door, lights): the
camera check shows it; re-run camtune if the light changes for good.

## Measured with the Kiyo (2026-11-12, home Wi-Fi)

The Kiyo offered 1920x1080 MJPEG at 30 fps only; `--desired-fps=10` gives
7-8 fps captured, ~22.5 Mbit/s, ~370 KB a frame. Enough: the engine needs a
fresh frame about once a second.

## Kiyo focus (locked, 2026-11-12; camtune automates this sweep)

Swept `focus_absolute` 0-255 in 5s, then 178-192 in 1s, scoring each frame with
`phase1.py locate` (sharpness = Laplacian variance, plus the ring fit). A sharp,
narrow peak: 187 = sharpness 629, rings 0.073 mm (auto focus: 466); half that 10
steps either side, rings lost beyond 170-205.

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
