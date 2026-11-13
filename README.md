# spotter

*A spotter tells you where your shot landed.*

An electronic scoring target for air pistol and air rifle **training**, built
from a webcam and a sheet of paper. No custom electronics.

A camera photographs the target card, locates the pellet hole, and scores it to
ISSF decimal precision.

```
  10m Air Pistol
  aiming mark : ring 7 = 59.5 mm
  axis ratio  : 0.8762  -> view ~29 deg off-axis
  model       : perspective + lens, from 10 rings
  ring fit    : 3483 points, RMS 0.076 mm (105 rejected)
  lens        : k1 -0.082  k2 -0.007
  perspective : scale varies 15.0% across the aiming mark
                true center is 6.3 px from the ellipse center
  scale       : 0.19900 mm/px at the center (5.0 px/mm)

  camera moved 0.04 mm between captures (scale change -0.02%)
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
   of precisely known diameter; an ellipse fitted to its edge gives a first
   centre and scale. That alone is not enough when the camera sits off to the
   side: a circle seen in perspective is still an ellipse, but its centre is
   not the ellipse's centre (at 37 deg that put the 10-ring ~1.8 mm off). So
   every printed ring line is then fitted too, solving a full perspective
   transform plus two lens-distortion terms - in every frame.
2. **Find the hole.** Each shot is compared with a frame taken before it,
   registered through the target's own geometry, so only new light counts.
   A sound trigger says *when* to look; the camera also checks on its own
   every second, so a shot that made no sound is still found.
3. **Score it.** Convert to target millimetres through that model, then apply
   ISSF ring geometry (decimal scoring, the edge nearest the centre counts).

The first step is the important one. Because the geometry is re-derived from
the card each frame, camera drift simply cancels - the hole is measured
relative to the target, never to the sensor. Measured drift of 0.53 mm over 37
minutes has no effect on the score.

## Measured performance

| | result | budget |
|---|---|---|
| geometry, synthetic cards 0-45 deg off-axis, exact truth | worst **0.018 mm** | 0.2 mm |
| the same test, aiming-mark ellipse only (the old model) | 1.6-6.3 mm | 0.2 mm |
| geometry noise, real camera ~37 deg off-axis (`bench`) | **0.003 mm** | 0.2 mm |
| hole detector, synthetic holes at known positions | 0.0008 mm | |
| ring fit residual, real cards | 0.08-0.20 mm RMS | |
| ring matches the shooter's call, real shots (unseen card) | 9 of 10 | |

The 0.2 mm budget is what air pistol decimal scoring needs (one decimal is
0.8 mm of radius). Geometry noise is far inside it.

What limits accuracy on real cards is the **paper**, not the camera:

- **Torn holes.** Pellets tear paper targets into holes 7-13 mm long, and the
  pellet's own mark is then a judgement call. On a 10-shot card not used for
  tuning, 9 rings matched the shooter's call and the miss was flagged. Shots
  within ~0.5 mm of a line are flagged as line calls for the shooter to decide.
- **Card flatness.** Off-axis, a bump of height h shifts by about h x tan(view
  angle). Real cards show up to ~0.4 mm of this; mount the card flat.
- **Overlapping shots.** A known-diameter circle is fitted to the round part
  of the hole's edge (2 mm separation: 0.61 -> 0.04 mm error in synthetic
  tests). Not yet proven on real overlapping holes.
- **Decimal accuracy on real shots is not yet verified** against a physical
  measurement (e.g. calipers). Whole rings are checked against the shooter's
  calls; decimals are repeatable but unconfirmed.

## Setup

```bash
cd engine
python3.15 -m venv .venv          # brew install python@3.15
./.venv/bin/python -m pip install -r requirements.txt
./.venv/bin/python probe.py        # check camera access
./.venv/bin/python cameras.py      # find your camera's index
```

On macOS, grant camera access in **System Settings > Privacy & Security >
Camera** to Terminal or VS Code, then fully restart that app.

The announcer's voices come with the repo: every piece it says, in all 19 Kokoro
voices, is in `web/public/voice-pieces`, and the range screen plays them in the
browser. Kokoro itself (its own Python 3.13 environment, a ~350 MB model) is only
needed to render new lines - chatty mode's commentary, or reworded announcements:

```bash
brew install python@3.13
engine/voice/setup.sh
engine/voice/.venv/bin/python engine/voice/speak.py say --voice af_heart "shot 3. 8.5, shot high left"
```

## Usage

```bash
cd engine
./.venv/bin/python phase1.py live              # real-time HUD for aiming the camera
./.venv/bin/python phase1.py locate            # show derived geometry + overlay
./.venv/bin/python phase1.py score             # find and score every hole
./.venv/bin/python phase1.py shot --expect 1   # before/after: score the new shot
./.venv/bin/python phase1.py bench --label light-on   # measure the rig, A/B lighting
```

`--target rifle` switches to air rifle. `--image <path>` works from a saved
file instead of the camera. `--device N` picks the camera.

`live` is the one to start with — it solves the geometry in real time and tells
you which way to move things:

```
  view    camera may sit off to the side; ring fit RMS want <= 0.25 mm
  RMS     want <= 0.50 px  focus
  fill    want 85-95%      move closer / further
  offset  want ~0,0        recentre the card
```

## Validation

```bash
cd engine
./.venv/bin/python selftest.py     # synthetic frames, no camera needed
./.venv/bin/python scoring.py      # ring tables and scoring boundary checks
```

`selftest.py` generates holes at known sub-pixel positions and confirms the
detector recovers them to 0.0008 mm — establishing that the algorithm is never
the limiting factor, so any worse result on real frames comes from optics,
lighting or rig stability.

## Rig

- Camera may sit off to the side, out of the line of fire (tested to 45 deg).
  Perspective and lens distortion are solved from the printed rings each frame
- Card mounted **flat**: off-axis, a bump of height h shifts by ~h*tan(angle)
- Even lighting, no specular glare; backlighting is better than front lighting
- Card centred, filling 85-95% of frame height
- Everything rigidly mounted

## Status

Working: geometry, hole detection, scoring, hands-free shot detection (sound
and camera), a web app (`web/`, see [web/README.md](web/README.md)) with a setup
wizard, live range screen, shot review, card statistics, practice / match /
final modes with a virtual range officer, and a natural announcer voice.

Also built: guns and pellets, a session diary, a journal with trends against a
goal (default 565 for air pistol), printable session and journal reports (save
as PDF), and a Shotmetrix QR export.

Not yet built: CSV export, announcer personalities, Raspberry Pi
deployment (Pi as camera only).

See [CLAUDE.md](CLAUDE.md) for architecture, domain details, and the gotchas
worth knowing before changing any of it.

## Licence

[PolyForm Noncommercial 1.0.0](LICENSE)
