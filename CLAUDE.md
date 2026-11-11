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

The repo has two halves: **`engine/`** (Python: camera, mic, geometry, scoring;
its own `.venv`, its run data in `engine/out/`) and **`web/`** (Rails). Shared
things stay at the root: `docs/` (the contract between them), this file, README.
The engine files below live in `engine/`; run engine commands from there.

| file | role |
|---|---|
| `scoring.py` | ISSF ring geometry + score. Pure maths, no OpenCV. |
| `geometry.py` | Find the target in the image, from the target itself. |
| `phase1.py` | Main CLI: `live` / `locate` / `score` / `shot` / `bench` |
| `target0.py` | Hole detection + Phase 0 rig tools (`jitter`, `drift`, ...) |
| `selftest.py` | Synthetic validation of detector AND off-axis geometry. No camera. |
| `cameras.py` | Enumerate cameras, map OpenCV indices to names |
| `audio.py` | Camera-mic shot TRIGGER (not positioning): impulse events vs running floor |
| `report.py` | Posts engine events to the web app (`--report-to`), off the scoring thread |
| `camstream.py` | Serves a local camera as MJPEG: tests the Pi stream path on the laptop |
| `web/` | Rails 8.1 range screen + shot review (SQLite, Hotwire, ViewComponent, RSpec). See `web/README.md` |
| `docs/engine-events.md` | THE contract between engine and web app. Change both sides together |
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
cd engine
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

## Web app (`web/`, 2026-11)

Rails 8.1 · Ruby 4.0.9 · **SQLite** (a range device, later a Pi: no DB server) ·
Hotwire · Tailwind v4 · ViewComponent · RSpec + FactoryBot. Follows fl-shooters'
conventions (`../fl-shooters`; button/card/base components and palette copied
from there). The user commits; don't commit unless asked.

- Engine and web app are separate processes in one repo. The engine POSTs every
  event (`shot --auto --report-to http://localhost:3000`) from a background thread
  and never waits on the web app; the web app stores it and pushes it live
  (Turbo Streams; `LiveBroadcast` replaces whole panels).
- Events API: localhost-only unless `SPOTTER_TOKEN` is set (then Bearer token).
- **Proposal vs call:** a `Shot` keeps the rules' proposal (position, score, flags,
  every estimate, geometry health, frames, straightened close-ups) and the
  shooter's call (ring, decimal, TAPPED POSITION, note) in separate columns; their
  difference is the training label for the planned model that will replace the
  hand-written rules (fl-shooters stores proposal vs final holes the same way).
  Displayed scores go through `Shot#final_*` (the call wins).
- Close-ups are straightened top-down at 20 px/mm (`report.closeup`), so a tap is
  a position in target mm and the patches are uniform for training.
- `TargetSpec` (Ruby) and `shot_call_controller.js` re-implement `scoring.py`'s
  arithmetic; `spec/models/target_spec_spec.rb` pins the same values. Change all
  three together. Positions are mm, x right, **y UP** (fl-shooters stores y down).
- Time zone defaults to Eastern (`SPOTTER_TIME_ZONE` overrides).

Not built yet (agreed order): live MJPEG camera view (`--stream`, from the engine:
only one process can hold the camera), import of the pre-web `engine/out/shots` log,
session history with trends, match/final timing and a virtual RO (freETarget
has both), and the model trained from reviewed calls.

## Deployment direction: Pi = camera, laptop = everything else (2026-11)

The shooter has a **Raspberry Pi 3** and shoots alone. Decided: the Pi at the
target ONLY streams the Kiyo (MJPEG over Wi-Fi; `ustreamer` on the Pi, which
forwards the camera's own MJPEG without re-encoding); the laptop at the firing
line runs the engine and the web app. Reasons: a Pi 3 cannot run the engine
(geometry fit ~0.25 s/frame on the laptop, likely 10-20x slower on a Pi 3, and the
2 s camera check would not keep up), and a Pi 5 needs 5 V / 5 A, which ordinary
power banks and tool-battery USB adapters do not provide (USB-PD caps 5 V at
3 A). A Pi 3 runs off any power bank.

- `--device` takes a camera index OR a stream URL (`target0.parse_device`).
  `_LiveCamera` reports "camera connection LOST" after 3 s without frames and
  reopens every 2 s; `grab` raises `CameraLost` meanwhile. `--auto` keeps its
  baseline through an outage (a shot fired meanwhile is found by the camera
  check once frames return) and says "camera connection lost" at most once a
  minute.
- `engine/camstream.py` serves a local camera as MJPEG, to test the stream path
  on the laptop without a Pi. Python's HTTPServer looks up the host's FQDN on
  bind, which HUNG on macOS: `Server.server_bind` skips it.
- **JPEG compression does not affect scoring:** re-scoring six real shots from
  JPEG frames, quality 95/85/75 kept every score; positions moved <= 0.02 mm.
  1080p at JPEG q95 and 15 fps measured ~32 Mbit/s - too much for a Pi 3's
  2.4 GHz Wi-Fi (~20-40 Mbit/s real); lower fps or quality on the Pi.
- Sound trigger options with the Kiyo's mic now at the target: (1) the laptop
  mic at the firing line hears the GUN (loud, 1 m away; other shooters' guns are
  rejected by the no-new-hole check), (2) run `audio.py` on the Pi and send only
  triggers, (3) camera-only (2-4 s per shot). Start with (1); thresholds were
  tuned on the Kiyo hearing impacts and must be re-measured (`listen --mic`).
- Not done yet: Pi setup (`pi/`: ustreamer service, v4l2-ctl to LOCK focus and
  exposure - impossible on macOS, which caused the frame-to-frame focus/scale
  drift), measuring real fps/bandwidth/latency from the Pi 3.

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
- `shot --auto` announces each result (macOS `afplay` + `say`): Glass +
  spoken score = ok; Sosumi + "check shot N, <reason>" = flagged; Basso +
  "shot not scored" = failed. `--no-speak` turns it off. Through a laptop
  speaker near the Kiyo, Basso measured +52.6 dB (over a shot); `--speaker`
  ignores the mic while an announcement plays. Default is OFF (earbuds).
  "not scored" is spoken at most once per 10 s as a loop backstop.
- **The camera is a second trigger** (2026-11: one real shot made no sound
  trigger; the next comparison held two holes and `--expect 1` dropped one).
  Every `--watch` s the camera compares the card with the baseline; a
  hole-sized new region (peak >= 40, area >= half a pellet) still there on the
  next check is scored and announced "found without a sound". Sounds within
  12 dB of the trigger threshold are always printed, so a quiet miss is
  visible next time.
- **Movement guard** (2026-11 phantom: a magnet's clang while the shooter -
  caught in the baseline - mounted the card). `_scene_moving` = >1% of the
  card bbox changed beyond everything nearby, BOTH directions (a plain
  |difference| counted shifted printed lines as movement, and the resulting
  re-baseline SWALLOWED a real hole). A capture whose view changed that much
  is not scored; after movement, once still for two checks, a fresh baseline
  is taken - but only after checking the old baseline for a new hole first.
- `_scene_moving` is measured INSIDE RING 1 only: the card's outer edge is
  beyond the fitted rings, its registration is an extrapolation that shifts
  2-3 px between frames minutes apart, and the outline alone read 2.1%
  "changed" on a still scene - enough to reject a real shot. Real shot pairs
  read 0.10-0.46% against the 1% limit. A movement rejection is announced and
  its frames saved; it is never silent.
- Ctrl+C runs a FINAL CHECK for an unscored hole (waits up to ~6 s for a still
  view): the last shot of a session has no later check to catch a missed
  sound (2026-11: the 10th shot of a string was lost this way).
- Sound misses EXPLAINED (2026-11 output): the announcement mute stamped an
  announcement's end lazily, at the next sound - so the next SHOT was
  "ignored: own announcement" (7 shots in one string; the camera net rescued
  most). Fixed (`_track_announcements` every loop pass), and the mute is now
  OFF unless `--speaker` (the shooter uses earbuds). Shots also ran as quiet
  as +48.5 dB: trigger is now >= +45 dB AND >= 180 ms (shots 204-370 ms;
  card-change / magnet sounds at most 160 ms).
- A re-baseline after movement must not proceed when the hole it found could
  not be scored (that swallowed the 10th shot); it keeps the old baseline for
  up to 3 tries, then warns.
- **Card changes are detected** in `--auto`: every `--watch` s (2) between
  shots it checks the target is in view. Gone for 2 checks = "card off"; back
  for 2 checks = new baseline, and `_same_card` decides new vs same card by
  whether the earlier holes (bright through the diffuser) are still at their
  positions - new card clears the earlier-hole list used by the overlap check.
  Validated on saved frames: same card / same card pre-holes / different card.
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
- **Eye calls on a FINISHED card are contaminated by later shots.** Shot 011
  was ~0.3 mm short of the 8 line when fired (system 7.9); a later shot tore
  the paper between them, so on the finished card it "touched" and was
  called 8. Ground truth must come from the photo taken right after each
  shot (`out/shots/NNN_after.png`) or a call made before the next shot - the
  shot-by-shot capture sees each hole before later damage.
- **Touch rule is "pellet" (default for `shot`, 2026-11).** Reviewing shots
  one by one, the shooter judges by the PELLET'S OWN MARK - folding tears
  back - not the visible tear. Fitted on 20 shooter-called real shots:
  position = region CENTROID (the circle fit chose the wrong end of a tear
  several times; the shooter said the centroid was closer 4 of 6 times), mark
  diameter `PELLET_MARK_MM` = 4.5 + 2*0.65 mm. Matches 20/20 (plain 4.5 mm
  gauge 17/20 - it always erred OUTWARD; visible-hole rule 18/20 - a tear
  reaching a line the pellet did not). 0.65 is mid-window (0.45..0.91), so
  only ~0.2 mm margin: LINE CALL / RING UNCERTAIN flags stay essential
  (5 of 19 flagged). Overlapping an earlier hole -> circle-fit position (the
  centroid is dragged into the old hole). `--rule gauge|visible` remain.
  OUT-OF-SAMPLE CHECK (2026-11, first 10-shot single card, 044-053, not used
  for tuning): 9/10 rings right; the miss (049, called 8, scored 9.0) was
  flagged LINE CALL. Re-fit on all 30 calls: centroid + 0.5-0.8 mm = 29/30;
  037 (needs >= ~0.45) and 049 (needs <= ~0.25) contradict each other by
  ~0.2 mm - that is the measurement's precision on torn paper, so line calls
  stay flagged and the shooter decides. Circle fit vs centroid as the better
  position: split (shooter picked fit 4x, centroid 3x on that card).
  The visible rule's implementation notes (`target0.visible_edge`): reads the
  PLAIN difference at 30% of peak, all fragments - see git history.
- **Line calls go both ways within ~0.4 mm** - not a bias: 006 and 013 (gauge
  rule) read 0.03 / 0.36 mm outside lines the shooter saw touched; 021b
  (visible rule) read 0.10 mm INSIDE a line the shooter saw clear. The 0.5 mm
  LINE CALL flag caught every one; the shooter's call is final on flagged
  shots (recorded in `your_call`).
- **Line calls may lean outward.** Two touching-line shots the shooter called
  (006: 7, 013: 6) the system put just OUTSIDE the line (013: 0.36 mm). Either
  the eye judges the visible torn hole (wider than the 4.5 mm the system and
  the official plug gauge use) or there is a small outward bias - not yet
  separated. `LINE_CALL_MM` widened 0.25 -> 0.5 mm so these get flagged.
- **Diffuser behind the target (2026-11):** a sheet of printer paper ~1-2 cm
  behind the card, lit by the trap's side LEDs, makes holes BRIGHT everywhere
  (they were dark-on-black in the bull). Side effects: holes on the aiming
  mark's rim notch its outline, so `find_target_frame` judges roundness on the
  convex hull (+ solidity >= 0.85, or a frame-shaped background passes); a
  wide torn target hole can line up with a diffuser hole and show a dark patch
  that splits the region (replace the diffuser often). Holes still tear to
  7-13 mm on this paper; that needs card targets / wadcutters, not light.
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
