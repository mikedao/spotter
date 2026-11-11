# CLAUDE.md

Camera-based electronic scoring target for **air pistol / air rifle training**.
A webcam photographs a paper target, finds the pellet hole, and scores it to
ISSF decimal precision.

## Why this exists

Started from a clone of [freETarget](https://github.com/ten-point-nine/freETarget),
which triangulates shots acoustically with four microphones. Two approaches
were evaluated and **rejected** — do not re-litigate these:

- **"Raspberry Pi replaces the custom board"** — impossible. freETarget times
  acoustic arrival on a 10 MHz clock (100 ns = 0.034 mm) and decimal scoring
  needs ~300 ns. Linux GPIO interrupt latency is tens of microseconds with
  unbounded jitter; a 50 us hiccup is 17 mm of error. No software fixes it.
- **Pi + Pi Pico hybrid** — technically the best acoustic option (PIO gives
  ~7 ns), but every acoustic variant still needs the analog front end: 4x
  electret mic + preamp + comparators with a programmable threshold. Rejected
  on hardware build burden.

Camera was chosen because it needs **no custom hardware**. The trade: it throws
away nearly all of freETarget's firmware (that code is almost entirely acoustic
timing) and replaces it with computer vision.

## Status

Phase 0 (feasibility) and Phase 1 (self-locating scorer) both **work**.

| measurement | result | budget | verdict |
|---|---|---|---|
| within-run noise floor | 0.0073 mm | 0.2 mm | PASS, ~27x margin |
| bull edge fit | 0.19 px RMS | — | excellent |
| camera drift over 37 min | ~0.53 mm | 0.2 mm | handled by design, see below |
| overlap limit | ~4 mm separation | — | open, see Phase 2 |

Real card scored end to end: **9.4 decimal / ring 9**.

## Architecture

| file | role |
|---|---|
| `scoring.py` | ISSF ring geometry + score. Pure maths, no OpenCV. |
| `geometry.py` | Find the target in the image, from the target itself. |
| `phase1.py` | Main CLI: `live` / `locate` / `score` / `shot` |
| `target0.py` | Hole detection + Phase 0 rig tools (`jitter`, `drift`, ...) |
| `selftest.py` | Synthetic validation of the detector. No camera needed. |
| `cameras.py` | Enumerate cameras, map OpenCV indices to names |
| `probe.py` | Camera permission / resolution check |

### The central design idea

**There is no fixed pixel-to-mm calibration.** Centre and scale are re-derived
from the card's own black aiming mark in *every frame*. Camera drift, thermal
creep and mount settling therefore cancel out completely, because the hole is
only ever measured relative to the **target**, never to the sensor.

This is not a refinement — it is the reason the 0.53 mm drift does not matter.
Never reintroduce a static scale. `calib.json` survives only as an optional ROI
crop (`--roi`) and its `mm_per_px` is deliberately ignored.

## Running it

```bash
./.venv/bin/python phase1.py live          # real-time HUD for aiming the camera
./.venv/bin/python phase1.py locate        # derived geometry + ring overlay
./.venv/bin/python phase1.py score         # find and score every hole
./.venv/bin/python phase1.py shot --expect 1   # before/after, scores the new hole
./.venv/bin/python selftest.py             # synthetic check, no camera
```

Add `--image out/snap_raw.png` to any command to work from a file.
Add `--target rifle` for air rifle.

Rig: Razer Kiyo on **OpenCV device index 2** (`cameras.py` re-checks this).
macOS blocks camera access until Terminal/VS Code is granted it in
System Settings > Privacy & Security > Camera, then fully restarted.

## Domain facts (verified against a physical card)

Ring diameters follow `d(n) = d10 + (10 - n) * step_d`.

| | 10m Air Pistol | 10m Air Rifle |
|---|---|---|
| 10-ring | 11.5 mm | 0.5 mm |
| step (DIAMETER) | **16 mm** | 5 mm |
| black aiming mark | ring **7** = 59.5 mm | ring **4** = 30.5 mm |
| outer ring 1 | 155.5 mm | 45.5 mm |
| decimal step (radius) | 0.80 mm | 0.25 mm |
| card | 170 mm | 80 mm |

Air pistol steps **16 mm in diameter, not 8**. Getting this wrong puts the
black mark at ring 4 and the outer ring at 83.5 mm, and the ring overlay then
visibly fails on a real card. The rifle table reproduces freETarget's
`AirRifle.cs` exactly, which is the cross-check.

Decimal scoring is **piecewise**: outside the 10-ring each ring divides into
ten bands of `step_radius/10`; inside the 10-ring the disc divides into ten
bands so dead centre reads 10.9. Treating the 10-ring as just another annulus
gives a maximum of 10.7 and is wrong.

Scoring uses the hole EDGE nearest the centre (`r_edge = r - pellet/2`),
because ISSF awards the higher value when the hole touches the line.

## Gotchas that cost real time

**Detector (`target0.detect_holes`)**
- Plain Otsu fails on a real target: paper is brighter than the black bull, so
  "brighter than average" selects the paper and its grain fragments into ~55
  false blobs. Use the white **top-hat** (SE ~3x hole width) plus a roundness
  filter.
- Gaussian blur must be **scaled to the hole** (`sigma = hole_px/8`). Paper
  grain is 1-3 px, a hole is ~28 px. With too little blur the morphological
  opening tracks the grain minimum, the top-hat reads large everywhere, and the
  noise-based threshold explodes past 255 and finds nothing.
- Threshold is `median + 5*MAD` of the top-hat. Never use a fraction of the
  global max: one bright artefact elsewhere drags the floor above the hole's
  own peak and erodes it to a tiny core.
- Blur inflates blob areas, so the overlap "% of a full hole" reference must be
  measured from a real baseline hole, not computed from pellet diameter.

**Geometry (`geometry.py`)**
- `flatten_illumination` is mandatory before thresholding. A 68-level lighting
  gradient made Otsu merge a dim corner with the bull into one blob covering
  27.8% of frame at circularity 0.249.
- `refine_bull_ellipse` search window must be **0.85-1.15x** the bull radius.
  The printed white rings INSIDE the black (ring 8 sits at ~0.73 of the bull
  radius) will capture the rays if you search further in — that produced a
  38 px RMS garbage fit.
- A downscaled solve returns edge RMS in **downscaled pixels**. Divide by the
  scale factor or the focus check is silently too lenient.

**Registration (`shot`)**
- Before/after frames are registered through the target via
  `geometry.align_matrix` before differencing. Without it, camera movement
  turns every printed ring line into a bright edge. A real run produced **55
  phantom shots**.
- Diagnostic: evenly spaced detections at constant x or y, **exactly one ring
  apart** (8 mm for pistol), always means registration error, never shots.
- `cv2.warpAffine` needs **`WARP_INVERSE_MAP`** here. `align_matrix` returns an
  after->before map, which is already the inverse map warpAffine wants; without
  the flag OpenCV treats it as forward and DOUBLES the error.
- Do not set `min_circularity=0` to let overlap crescents through. It disables
  the filter entirely and floods the results.

**Platform**
- On macOS, OpenCV/AVFoundation reports `autofocus=-1 auto_exposure=-1
  auto_wb=-1`: these cannot be locked from code. Work around it by killing room
  lights so the dominant light source is stable. Proper control returns on the
  Pi via `v4l2-ctl`.

## Known limits / next up

- **Overlapping shots.** A 4.5 mm pellet needs ~4 mm separation. Measured error:
  4 mm -> 0.08 mm, 3 mm -> 0.42 mm, 2 mm -> 0.83 mm. The error is
  **systematic, not noise** (the centroid of a visible crescent is not the
  centre of the pellet), so frame averaging cannot help.
  **Planned fix:** fit a circle of known 4.5 mm diameter to the crescent's
  outer arc instead of taking its centroid.
- Frame averaging buys nothing (1-frame and 16-frame are identical), so the
  system is not sensor-noise limited. Single frames are fine and faster.
- Lighting is currently front-lit with glare. Backlighting is better: the air
  rifle target's whole high-value area is black paper, where a hole is
  invisible under front light. Backlit, a hole is bright on a dark field.
- Not yet built: shot-to-shot session logging, training metrics
  (group size, mean radius, trend), piezo auto-trigger, Raspberry Pi
  deployment, web UI.

## Conventions

- Verify against physical measurements, not assumptions. The ring-spacing error
  and the tilt-vs-pixels question were both settled by measuring the real card,
  not by reasoning about it.
- When a result looks good, check what the test *cannot* see. `jitter` passed
  with 14x margin while being structurally blind to the 0.53 mm drift, because
  it references every round against round zero of the same run.
- Keep `selftest.py` passing. It establishes that the algorithm is not the
  limiting factor, so any worse result on real frames is optics, lighting or
  rig stability.
