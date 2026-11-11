# Camera Target Scorer

An electronic scoring target for air pistol and air rifle **training**, built
from a webcam and a sheet of paper. No custom electronics.

A camera photographs the target card, locates the pellet hole, and scores it to
ISSF decimal precision.

```
  10m Air Pistol
    aiming mark : ring 7 = 59.5 mm
    centre      : (960.53, 451.92) px
    axis ratio  : 0.9911
    scale       : 0.18035 mm/px
    edge fit    : 334 points, RMS 0.19 px

     #     x mm     y mm     r mm  score  ring
     0    -0.19   +12.55    12.55    9.4     9
```

## Why a camera

The usual DIY approach — [freETarget](https://github.com/ten-point-nine/freETarget)
and similar — triangulates the shot acoustically from four microphones. That
works very well, but it needs a custom board: microphone preamps, comparators
with a programmable threshold, and hardware counters timing to 100 ns.

A camera needs none of that. The catch is that precision moves from the time
domain to the geometry, which is where all the interesting work is.

## How it works

1. **Find the target from the target.** The black aiming mark is a filled disc
   of precisely known diameter, so fitting an ellipse to it gives centre and
   scale — in every frame.
2. **Find the hole.** A white top-hat transform isolates small bright features
   against the local background; a roundness filter rejects paper grain and
   glare.
3. **Score it.** Convert to target millimetres, then apply ISSF ring geometry.

The first step is the important one. Because the geometry is re-derived from
the card each frame, camera drift simply cancels — the hole is measured
relative to the target, never to the sensor. Measured drift of 0.53 mm over 37
minutes has no effect on the score.

## Measured performance

| | result |
|---|---|
| noise floor (centroid repeatability) | **0.0073 mm** |
| air pistol decimal budget | 0.2 mm |
| margin | ~27x |
| bull edge fit | 0.19 px RMS over 334 points |

The known limit is **overlapping shots**: a 4.5 mm pellet needs about 4 mm of
separation before accuracy degrades, and the error is systematic rather than
random. A fix is planned (fitting a known-diameter circle to the visible
crescent rather than taking its centroid).

## Setup

```bash
python3 -m venv .venv
./.venv/bin/python -m pip install opencv-python numpy
./.venv/bin/python probe.py        # check camera access
./.venv/bin/python cameras.py      # find your camera's index
```

On macOS, grant camera access in **System Settings > Privacy & Security >
Camera** to Terminal or VS Code, then fully restart that app.

## Usage

```bash
./.venv/bin/python phase1.py live              # real-time HUD for aiming the camera
./.venv/bin/python phase1.py locate            # show derived geometry + overlay
./.venv/bin/python phase1.py score             # find and score every hole
./.venv/bin/python phase1.py shot --expect 1   # before/after: score the new shot
```

`--target rifle` switches to air rifle. `--image <path>` works from a saved
file instead of the camera. `--device N` picks the camera.

`live` is the one to start with — it solves the geometry in real time and tells
you which way to move things:

```
  ratio   want >= 0.990    square the camera to the card
  RMS     want <= 0.50 px  focus
  fill    want 85-95%      move closer / further
  offset  want ~0,0        recentre the card
```

## Validation

```bash
./.venv/bin/python selftest.py     # synthetic frames, no camera needed
./.venv/bin/python scoring.py      # ring tables and scoring boundary checks
```

`selftest.py` generates holes at known sub-pixel positions and confirms the
detector recovers them to 0.0008 mm — establishing that the algorithm is never
the limiting factor, so any worse result on real frames comes from optics,
lighting or rig stability.

## Rig

- Camera square to the card (this matters — tilt was worth 10% distortion)
- Even lighting, no specular glare; backlighting is better than front lighting
- Card centred, filling 85-95% of frame height
- Everything rigidly mounted

## Status

Working: geometry, hole detection, scoring, before/after shot detection with
registration.

Not yet built: session logging, training metrics (group size, mean radius,
trends), piezo auto-trigger, Raspberry Pi deployment, web UI.

See [CLAUDE.md](CLAUDE.md) for architecture, domain details, and the gotchas
worth knowing before changing any of it.

## Licence

[PolyForm Noncommercial 1.0.0](LICENSE)
