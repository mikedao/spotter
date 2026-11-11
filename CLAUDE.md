# CLAUDE.md — spotter

Camera-based electronic scoring target for **air pistol / air rifle training**.
A webcam photographs a paper target, finds the pellet hole, and scores it to
ISSF decimal precision.

Named for the spotter at a range: the thing that tells you where your shot
landed.

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

**Camera now sits off to the side** (out of the line of fire), ~37 deg off-axis
on the 2026-11 rig. The geometry is a full perspective + lens-distortion model
fitted to every printed ring, per frame:

| measurement (off-axis rig) | result | budget |
|---|---|---|
| synthetic, 0-45 deg, exact truth | worst 0.018 mm | 0.2 mm |
| old ellipse-only model, same test | 1.6-6.3 mm | 0.2 mm |
| geometry score noise, real Kiyo (`bench`) | 0.003 mm | 0.2 mm |
| ring fit residual, real card | 0.20 mm RMS, structured | see card flatness |

## Architecture

| file | role |
|---|---|
| `scoring.py` | ISSF ring geometry + score. Pure maths, no OpenCV. |
| `geometry.py` | Find the target in the image, from the target itself. |
| `phase1.py` | Main CLI: `live` / `locate` / `score` / `shot` / `bench` |
| `target0.py` | Hole detection + Phase 0 rig tools (`jitter`, `drift`, ...) |
| `selftest.py` | Synthetic validation of detector AND off-axis geometry. No camera. |
| `cameras.py` | Enumerate cameras, map OpenCV indices to names |
| `audio.py` | Camera-mic shot TRIGGER (not positioning): impulse events vs running floor |
| `probe.py` | Camera permission / resolution check |

### The central design idea

**There is no fixed pixel-to-mm calibration.** Centre and scale are re-derived
from the card's own black aiming mark in *every frame*. Camera drift, thermal
creep and mount settling therefore cancel out completely, because the hole is
only ever measured relative to the **target**, never to the sensor.

This is not a refinement — it is the reason the 0.53 mm drift does not matter.
Never reintroduce a static scale. `calib.json` survives only as an optional ROI
crop (`--roi`) and its `mm_per_px` is deliberately ignored.

The same applies to perspective and lens distortion: `geometry.fit_perspective`
solves a homography plus two radial lens terms (k1, k2, centred on the image
centre) from the aiming-mark edge and every visible ring line, in every frame.
`TargetFrame.to_mm` / `from_mm` go through that model; never map pixels to mm
any other way (no `cx + r/mm_per_px`, no `cv2.ellipse` of a ring).
`mm_per_px` is the scale *at the centre* only; under perspective it varies
~20% across the card, so use `local_mm_per_px(x, y)` for anything positional.

## Running it

```bash
./.venv/bin/python phase1.py live          # real-time HUD for aiming the camera
./.venv/bin/python phase1.py locate        # derived geometry + ring overlay
./.venv/bin/python phase1.py score         # find and score every hole
./.venv/bin/python phase1.py shot --expect 1   # before/after, scores the new hole
./.venv/bin/python phase1.py shot --expect 1 --count 5   # series; logs your by-eye call per shot
./.venv/bin/python phase1.py bench --label light-on   # A/B a rig/lighting change
./.venv/bin/python phase1.py listen --seconds 120      # what the camera mic hears
./.venv/bin/python phase1.py shot --auto              # hands-free, mic-triggered
./.venv/bin/python selftest.py             # synthetic check, no camera
```

Add `--image out/snap_raw.png` to any command to work from a file.
Add `--target rifle` for air rifle.

Rig: Razer Kiyo on **OpenCV device index 0** on the laptop (`cameras.py`
re-checks this; it was 2 on the previous machine).
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
- Scaling a downscaled solve back up must use `TargetFrame.scaled(k)`, which
  applies cv2.resize's pixel-CENTRE convention (`new = (old+0.5)k - 0.5`).
  Plain multiplication shifted everything ~0.7 px.
- The aiming mark alone **cannot** reveal perspective: a circle in perspective
  images as an exact ellipse, but its centre is not the ellipse's centre. At
  37 deg the ellipse model put the 10-ring ~1.8 mm off and ring 1 ~9 mm off.
  Only the concentric ring lines fix it.
- **Lens distortion is real on the Kiyo** (k1 ~ -0.19, k2 ~ +0.29). A
  homography alone left a ring-by-ring curve of -0.4 to +0.5 mm. That also
  means the old square-on rig carried uncorrected error at the outer rings.
- `fit_perspective` adds rings outward from the aiming mark in stages and only
  frees k1/k2 once every ring is in; the starting ellipse model is too far out
  at ring 1 to search there directly.
- **Card flatness matters off-axis.** A bump of height h shifts by ~h*tan(view
  angle). The real card left smooth +-0.4 mm residual patches shared by
  neighbouring rings (random part only 0.034 mm). `locate` warns when a ring's
  mean residual exceeds 0.1 mm. Mount the card flat.

**Registration (`shot`)**
- Before/after frames are registered through the target via
  `geometry.register` (dense remap: after-px -> mm -> before-px) before
  differencing. Without it, camera movement turns every printed ring line into
  a bright edge. A real run produced **55 phantom shots**. A 3x3 warp cannot
  express lens distortion, which is why this is a remap, not warpAffine.
- The difference is `geometry.new_light`: after minus a 5x5 MAX-filtered
  registered before. A plain difference lit every printed line and numeral
  (frames differ in sharpness/scale - autofocus is unlockable on macOS), gave
  up to 114 regions per shot, and LOST holes on the aiming-mark edge or a ring
  line by merging them with the line residue. 2026-11 series of 5 real shots:
  plain 3/5 rings matched the shooter's call, max-filter 5/5.
- Diagnostic: evenly spaced detections at constant x or y, **exactly one ring
  apart** (8 mm for pistol), always means registration error, never shots.
- Do not set `min_circularity=0` to let overlap crescents through. It disables
  the filter entirely and floods the results.

**Audio trigger (`shot --auto`)**
- The mic only says WHEN; vision says WHERE. This is not the rejected acoustic
  approach, which needed sub-microsecond timing for position.
- Measured 2026-11 (Kiyo mic, metal trap): shots clip at ~0 dBFS, +59 to +65 dB
  over the room floor, ringing 280-370 ms; a faint secondary sound follows
  ~0.7 s later. Loudest non-shot +43 dB. Defaults: trigger >= +52 dB and
  >= 100 ms, capture 1.0 s after impact, 2 s echo window.
- A trigger with no new hole is ignored AND the baseline is kept, so a missed
  hole can never be silently absorbed into the baseline.
- Never discard queued audio after scoring: a shot fired during scoring would
  be lost. The echo window handles the trap's ringing.
- The camera stays open in a reader thread (`_LiveCamera`); release it only
  after the thread leaves `cap.read()` or AVFoundation can hang.
- Testing from a script: background jobs ignore SIGINT, so Ctrl+C-style
  `kill -INT` does nothing there. Use plain `kill`.

**Platform**
- On macOS, OpenCV/AVFoundation reports `autofocus=-1 auto_exposure=-1
  auto_wb=-1`: these cannot be locked from code. Work around it by killing room
  lights so the dominant light source is stable. Proper control returns on the
  Pi via `v4l2-ctl`.

## Known limits / next up

- **Overlapping shots and paper tears: fixed in synthetic, NOT yet on real
  holes.** `target0.fit_pellet` fits a circle of the known 4.5 mm pellet
  diameter (in target mm, so off-axis ellipses are handled) to the round part
  of the region's half-height edge, by RANSAC. Synthetic: overlap at 2 mm
  separation 0.61 -> 0.04 mm; torn flaps 0.5-1.6 mm -> 0.03 mm. `shot` uses it
  when it finds >= 150 deg of round edge, else falls back to the centroid and
  says so.
  First real shot (paper target, 24 deg, torn ~11 mm long): the fit found only
  108 deg of arc and chose the tear's upper edge, not the round left end the
  shooter identified as the impact. Real tears are rougher than the synthetic
  model. `shot` saves every shot as `out/shots/NNN_before.png` / `NNN_after.png`;
  replay with `shot --before out/shots/NNN_before.png --image out/shots/NNN_after.png` and collect
  real cases (with the shooter's by-eye call) before tuning further.
- **Torn white-paper holes can be ~1 mm off.** Shot 006 (2026-11) touched the
  7 line by eye; the circle fit put its edge 1.23 mm outside (6.8), the
  centroid 0.03 mm outside. On another torn shot the centroid was the worse
  one. Neither is trusted alone: `report` flags RING UNCERTAIN when the span
  between the two estimates (+-0.25 mm, `LINE_CALL_MM`) crosses a ring line,
  and LINE CALL when the edge is within 0.25 mm of one. On white paper the
  hole itself looks DARK (dark backstop) inside a ring of bright torn fibres,
  and the light-change detector finds the fibres; a dark-change channel was
  tried and did not fix 006.
- Decimals are TRUNCATED (`scoring.score`), not rounded: rounding showed a
  ring-6 shot as "7.0".
- **Decimal accuracy on real shots is UNVERIFIED** (deliberately deferred).
  Integer rings matched the shooter's call on 5/5 real shots (2026-11), but
  calls were integers only. Holes straddling the aiming-mark edge are the
  weakest case (part of the hole is on white paper, low contrast); one moved
  7.2 -> 7.4 between differencing methods. To verify: caliper-measure centre
  to hole centre on a few holes and compare with `r_mm` in
  `out/shots/calls.csv`.
- **Static `score` loses holes near the white rings inside the black.** The
  top-hat keeps the white ring lines, and a hole within ~1.5 mm of one merges
  into a ring-sized blob that fails the size/roundness filters. It also picks
  up the white numerals. `shot` is unaffected (differencing cancels print).
  On the 2026-11 card `score` found 46 regions and neither real hole.
- **Oblique view of a hole** (unverified estimate): at 30-40 deg the camera sees
  part of the hole's inside wall, possibly shifting its apparent centre ~0.1 mm.
  Check with a physical measurement.
- `RING_LINE_MM = 0.2` (line centre half a width inside the nominal radius) is
  an assumption, not measured. Ring 10 fits +0.14 mm and the aiming-mark edge
  -0.09 mm on the real card, which may point at it.
- Live solve takes ~210 ms at half scale with the perspective fit.
- **Kiyo ring light: no effect on the card** (contrast 155 vs 154, geometry
  noise ~0.0025 mm either way once settled; light-on has slightly lower pixel
  noise, 2.3 vs 3.25). Its only effect was a flickering glint on a shiny object
  in the background, which `shot` counted as false shots. Detections are now
  limited to the card outline (`spec.card_mm`), so background changes are
  ignored. Wait ~30 s after touching the camera before measuring: the first
  light-on run right after pressing its button showed 4x the geometry noise.
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
