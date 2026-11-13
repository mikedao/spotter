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
| `liveview.py` | The engine's live picture (rings drawn on) for the range screen, `shot --auto --stream-port` |
| `web/` | Rails 8.1 range screen + shot review (SQLite, Hotwire, ViewComponent, RSpec). See `web/README.md` |
| `docs/engine-events.md` | THE contract between engine and web app. Change both sides together |
| `probe.py` | Camera permission / resolution check |
| `voicelines.py` | What the engine says, as pieces; the 19 Kokoro voices (shared with `voice/`) |
| `course.py` | Match / final courses of fire as data + the virtual range officer (`Runner`) |
| `voice/` | The Kokoro announcer: own Python 3.13 venv, `setup.sh`, `speak.py` (see "Announcer voice") |

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
./.venv/bin/python phase1.py listen --seconds 120      # what the default mic hears (--mic NAME)
./.venv/bin/python phase1.py shot --auto              # hands-free, mic-triggered
./.venv/bin/python selftest.py             # synthetic check, no camera
./voice/.venv/bin/python voice/speak.py say --voice af_heart "ready"   # the announcer
```

`shot --auto --course match|final|ranking` runs a course with the virtual range
officer; `kill -USR1 <pid>` ends a match's sighting time ("Start match").

Add `--image out/snap_raw.png` to any command to work from a file.
Add `--target rifle` for air rifle.

Rig: Razer Kiyo on **OpenCV device index 0** on the laptop (`cameras.py`
re-checks this; it was 2 on the previous machine).
macOS blocks camera access until Terminal/VS Code is granted it in
System Settings > Privacy & Security > Camera, then fully restarted.

## Setting up a machine (moving computers)

Code is in git; everything below is NOT, and has to be rebuilt or copied:

```bash
# engine: Python 3.15 (Homebrew), pinned requirements
cd engine && /opt/homebrew/bin/python3.15 -m venv .venv && ./.venv/bin/python -m pip install -r requirements.txt
./.venv/bin/python selftest.py                  # must pass

# announcer voice: ALREADY IN GIT for all 19 voices - the picker's samples
# (web/public/voice-samples) and every piece the engine says (web/public/voice-pieces,
# 5,662 files, 65 MB), so the range screen talks with no setup. Kokoro (Python 3.13 +
# ~350 MB model) is only needed to render NEW pieces: chatty mode's commentary lines
# (rendered at session start, ~40 min once per voice) and anything reworded.
brew install python@3.13 && voice/setup.sh
# after a wording change (voicelines.py / course.py): re-export, only new pieces render
#  voice/.venv/bin/python voice/speak.py export --all     # (and `samples` for the picker)
# chatty mode's lines are in git for SOME voices (Bella, Nicole, Heart, Michael); after a commentary edit:
#  (cd ../web && bin/rails voices:chatty_list)   # rewrites web/public/voice-pieces/chatty.txt
#  voice/.venv/bin/python voice/speak.py export --chatty --voice af_bella   # and af_nicole, af_heart, am_michael

# web: Ruby 4.0.9 (rbenv; web/.ruby-version), SQLite
cd ../web && bundle install && bin/rails db:prepare && bundle exec rspec   # 226 examples, 0 failures
bin/dev                                          # http://localhost:3000, sign up (username + PIN)
```

- **Not in git, copy by hand if wanted:** `engine/out/` (shot log `calls.csv`,
  every shot's before/after frames - the real-shot evidence behind "Known
  limits", and `engine/out/shots/044-053`, which `bin/rails spotter:demo` replays),
  `web/storage/*.sqlite3` (users, sessions, the shooter's CALLS - the future
  training set; else start fresh), `web/storage/voices/` (rendered chatty-mode
  lines; regenerate by themselves).
- macOS camera AND microphone permission for the terminal / VS Code that runs
  `bin/dev` (the engine inherits it), then restart that app.
- Re-check the camera index with `cameras.py` (Kiyo was 2, then 0, on the last
  two machines); the setup wizard shows pictures, so pick by what it sees.
- Stale on the 2026-11-11 laptop: a root-level `.venv`, `__pycache__`,
  `calib.json` and `out/` from before the `engine/` split - unused, ignore.
- **A database made before 2026-11-11's sign-in change** has email + password,
  not username + PIN: that commit EDITED the existing `create_users` migration
  instead of adding one, so an old database never gets the change (sign-in then
  fails: "no such column: users.username" / "One or more password arguments are
  required"). A fresh `db:prepare` is fine. On the old laptop it was repaired by
  hand (add `username`, rename `password_digest` -> `pin_digest`, then
  `users:reset_pin`). Never let `db:migrate` on such a database re-dump
  `schema.rb`: it writes the stale users table into the repo (happened once).
  Rule from this: add a NEW migration, never edit one that has run anywhere.
- Restart `bin/dev` after `bundle install` (a new gem, e.g. `rqrcode`, isn't
  loaded by a running server: "uninitialized constant ... RQRCode").

## Where we left off (2026-11-12, end of day)

All committed. Moving to another computer (see "Setting up a machine"; nothing
to copy unless the real-shot evidence / old sessions are wanted).

Built 2026-11-12 (all covered by specs; see "Web app" / "Announcer voice"):
guns + pellets (per lot), session diary, the JOURNAL (per-60 vs the 565 trials
benchmark, series, trend + forecast), session + journal REPORTS (print to PDF),
the SHOTMETRIX QR export, ring-only totals for pistol, card pages + deleting
shots (always renumbered), the FINISHED-session summary, range-screen layout
(zoom, ring numbers, sticky target, compact column), toast flash messages - and
the ANNOUNCER MOVED TO THE BROWSER: the engine hands each announcement to the web
app, the range screen plays it (Sound on/off), DIAGNOSTIC mode (off = number,
score, direction only) and CHATTY mode (written commentary, 10 phrasings per
moment), with every known voice piece for all 19 voices committed.

**Never yet tried for real - check these first:**
1. **The browser announcer on the rig:** Sound on, a few shots; diagnostic mode
   off and on; chatty mode (streaks, summaries every 10 shots, a match summary).
   Listen for lines that grate (wording is `config/commentary/default.yml` and,
   for the engine's own lines, `engine/voicelines.py` / `phase1.py`).
2. **Shotmetrix:** scan a real session's code with the Shotmetrix app (byte-exact
   against their test vectors and the QR decodes, but none redeemed yet).
3. **Print to PDF from Chrome** (session and journal reports; only checked as
   headless-Chrome PDFs).
4. **Still open from 2026-11-11:** setup wizard live with the Kiyo and a shot; a
   match / final end to end (clock, sighters, out-of-time zeros, session ends
   itself); the range officer's commands by ear ("load" / "start" / "stop");
   installing as an app; the camera fully visible during a live match on the
   laptop (a spec checks 1322x729).

**Next:** announcer PERSONALITIES to choose from (each a
`config/commentary/*.yml`; a picker in Settings). Chatty's lines are in the
git export for Bella, Nicole, Heart and Michael only (2026-11-12; 1,005 pieces each with the
numbers filled in, ~12 min per voice); other voices render them at session
start. Splitting the numbers out of the lines would make all 19 cheap.
Still open: CSV export; import of the pre-web `engine/out/shots` log (53 called
shots); the model trained from reviewed calls; Pi setup.

## Web app (`web/`, 2026-11)

Rails 8.1 · Ruby 4.0.9 · **SQLite** (a range device, later a Pi: no DB server) ·
Hotwire · Tailwind v4 · ViewComponent · RSpec + FactoryBot. Follows fl-shooters'
conventions (`../fl-shooters`; button/card/base components and palette copied
from there). The user commits; don't commit unless asked.

- Engine and web app are separate processes in one repo. The engine POSTs every
  event from a background thread and never waits on the web app; the web app
  stores it and pushes it live (Turbo Streams; `LiveBroadcast` replaces whole panels).
- **Users** (2026-11): Rails 8 authentication, OPEN sign-up, each user sees only
  their own sessions (every query goes through `Current.user`; another user's id
  is a 404). Sign-in is USERNAME + 4-8 digit PIN (`has_secure_password :pin`,
  username case-insensitive); email is stored, never used to sign in. No
  PIN-reset email (the app sends none): `bin/rails users:reset_pin LOGIN=... PIN=...`. Sign in/up at `/sign_in`, `/sign_up`;
  practice sessions at `/practice` (the login `Session` model is unrelated to
  `PracticeSession`).
- **The web app starts the engine** (decided over per-user tokens): Start creates
  the `PracticeSession` and `EngineRunner` spawns `phase1.py shot --auto` with
  `--session-id` and `SPOTTER_TOKEN=<session.run_token>`; the events API accepts
  only a session the web app created, with its own token. Stop = SIGINT = Ctrl+C
  (final check, then `session_ended`). One session at a time (one camera;
  `EngineRunner::Busy` says who). A watcher thread (and `reconcile!` on page load)
  ends a session whose engine died and keeps the log's tail in `engine_error`,
  shown live in `SessionStatusComponent`. Rig settings are env vars
  (`SPOTTER_CAMERA`, `SPOTTER_MIC`, ...; see web/README.md). Verified end to end:
  start -> ready -> stop -> ended, and a missing mic -> ended with the error.
- `engine/camstream.py --image FILE` streams a still photo as a camera: tests
  and demos without the rig.
- **Live rig checks MORPH** (`RigCheck::LiveProcess#push`: `attributes: { method:
  :morph }` - a plain `method:` option is silently dropped by turbo-rails 2.0):
  the camera check's picture is the same `<img>` across updates, so it no longer
  blanks and jumps every second; it keeps a 16:9 box. Specs use their own
  `tmp/setup-test` (they used to wipe the running app's camera check).
- **Voice prewarm: ONE per voice, 2 cores** (`speak.py prewarm` takes a lock in
  the cache; 2026-11-12 three at once, all cores each, pushed the load to ~170
  and slowed a live engine).
- **Flash messages are TOASTS** (`FlashComponent` + `flash_controller.js`, 2026-11-12):
  fixed over the top of the page (no layout shift); a notice fades after 5 s
  (held while hovered), an alert stays until closed (role="alert").
- **Confirmations are a MODAL, never the browser's confirm()** (2026-11-12, the
  shooter's call): `ConfirmDialogComponent` (in the layout) +
  `confirm_dialog_controller.js` registers itself as `Turbo.config.forms.confirm`,
  so a plain `data: { turbo_confirm: "..." }` is all a button needs. A DELETE form
  gets a red "Delete" with Cancel focused; otherwise "Continue", or name it with
  `data: { confirm_button: "Start match" }` on the form. Esc / outside click =
  cancel. spec/system/confirm_dialog_spec.rb.
- **It's an APPLICATION, not a website** (2026-11-11, the shooter's words): no
  top nav bar. The menu is a drawer that slides out over the content from a ☰
  floated beside each screen's heading (`drawer_controller.js`; Esc / outside
  click / link closes it); `main` has no max width, and the range screen's target
  grows to `100svh - 7.5rem` (cap 60rem). Installable as its own window
  (`/manifest`, `display: standalone`). Keep new screens app-like: no site chrome.
- **Match and Final modes** (2026-11-11). `engine/course.py`: courses of fire
  as DATA (`Say` / `Pause` / `Window`) and a `Runner` thread (the virtual RO)
  on the wall clock; the shot loop only asks `ro.classify(impact_time)`.
  Rules VERIFIED against the ISSF 2026 pistol rulebook: match = 60 shots in 75
  min after 15 min sighting (unlimited sighters); pistol qualification whole
  rings, finals/rifle decimals. Finals: the 2026 GTR 6.17 text could not be
  found, so BOTH formats exist, picked per session: `final` (classic 24-shot,
  freETarget / Paris 2024) and `ranking` (ISSF Dec 2022 doc: 5-shot series
  then medal-match singles; 8 singles here, the fewest that reach 16 points).
  Shooter's choices: "Start match" ends sighting early (SIGUSR1; the 30 s
  pause becomes 10 s); out of time / extra shots are FLAGGED AND SCORE ZERO.
  A camera-found shot gets 2x--watch grace (its time is when SEEN). Speech now
  plays one announcement at a time (`_Speech.LOCK`), RO commands with no tone
  (kind "ro"). Web: `Course` mirrors course.py (spec checks), `EventStats`
  (sighters excluded, penalties zero, series), `CoursePanelComponent` +
  `countdown_controller.js` (ticks to `ends_at` between events). The engine
  ends the session itself after "the results are final".
- **New session = a setup wizard, every time** (2026-11-11, the shooter's call:
  "Rig setup" as a separate page went). `SessionSetupController`,
  `/practice/new/{camera,check,microphone,start}`: pick camera + target, live
  camera check, sound check, then Start. GATED with escapes: Next unlocks at
  "Ready to shoot" ("Continue anyway") and once a sound would trigger ("camera
  only"); the panels carry the Next button so a Turbo broadcast unlocks it live.
  Each step `RigCheck.stop_for!(user)`s the previous check (SIGINT + wait) so the
  camera/mic are free; `Locate.clear!` on each new check so a stale "Ready"
  can't unlock it. Routes sit BEFORE `resources :practice_sessions`, else
  `practice/new/camera` hits the session's `camera` member route. Voice picker
  moved to Settings (`/settings`). UI says "session", not "match".
- **A passed sound check is remembered** (2026-11-12, the shooter: don't redo it
  for a setup that passed before): `users.sound_check` {mic, at, loudest_db,
  trigger_db, trigger_ms}, written when a check hears a shot that would trigger
  (`SessionSetupController#remember_sound_check`, on the microphone and start
  steps). The microphone step then REDIRECTS to Start when the user's mic passed
  before and is still in the last device search; Start says "✓ heard a shot
  (sound check Nov 12) - check again or change" -> `?again=1`. A different or
  missing mic asks again. (Not invalidated by a TRIGGER_DB change - stored for
  that, unused yet.)
- **Camera picker** (wizard step 1): New session / "Look again" runs `cameras.py --json DIR`
  (`CameraProbe`, ~5 s, refused while a session runs) and shows a preview per
  camera - pick by PICTURE, names are only a hint. Or a stream URL. Remembered as
  `users.last_camera`, recorded as `practice_sessions.camera`. The same probe
  lists microphones; choosing a NEW camera selects its own mic (`CameraProbe.pair`:
  same device name minus "camera"/"microphone"; `SessionSetupController#pair_mic`).
  `--mic none` = camera only: no sound trigger, every shot found by the camera
  check (2-4 s), and NOT flagged "found without a sound". The mic goes to the
  engine as one `--mic=NAME` argument; `valid_mic?` refuses control chars and a
  leading "-". `EngineRunner`
  accepts only `\d{1,2}` or an http(s)/rtsp URL (`BadCamera`), since it goes on
  the engine's command line.
- **Stop shows "Stopping" live, not as a flash** (a flash never went away):
  `EngineRunner.stop!` sets status `stopping` + broadcasts, then SIGINT. Engine
  events go through `PracticeSession#show_status!`, which never overwrites
  `stopping` (a shot found by the final check would read "Ready"); only
  `session_ended` (or `reconcile!`) ends it. Verified in Chrome.
- **Reviewing shots walks the whole SESSION** (`ShotReview`): every scored shot,
  cards in order. "Save and next" = next shot WITHOUT a call after this one,
  wrapping to the start (it used to go forward on the same card only, so opening
  shot 5 never visited 1-4 or later cards); the save completing the review goes
  back to the session; if all were already called, it steps on in order.
  `after_save` must be asked BEFORE `record_call!`. Shot page shows "Shot N of M"
  and previous/next links.
- **Scoring a capture by hand** (2026-11-12): an unscored capture's page shows its
  after picture - tap the hole, "Score this hole". `ShotPinpoint` runs the ENGINE's
  `phase1.py pinpoint --image AFTER --before BEFORE --px X Y --out DIR` (locates
  the target in THAT frame, perspective + lens; the tap -> target mm; writes the
  straightened close-ups), then `Shot#score_by_hand!`: scored by the Ruby
  `TargetSpec` (pellet rule), placed in FIRING ORDER (later shots on the card
  renumber; in a match it takes the stage of the shot before it and the next
  competition number, later ones renumbered), `pinpointed_at` set = "scored by
  you" (badge; the shot page says "Placed by you, by hand"). Fine-tune with the
  usual call circle. Verified: a round trip on real shot 044 came back within
  0.001 mm; a real-Chrome tap on its picture scored 6.5 like the engine (0.1 mm,
  click precision on the downsized picture). Not built: adding a shot the system
  never saw at all (no capture).
  MID-SESSION (the shooter: "it says not scored - can I simply plot a shot?"): the
  live range screen's latest panel shows "Shot not scored - Plot it ->" (and
  "Not scored" rows in the list link the same way); it loads the capture into a
  `<dialog>`'s turbo-frame (`ShotsController#plot`, `plot_dialog_controller.js`)
  OVER the range screen - never leave the page, or the sound stops. Scored, the
  frame shows the result and the dialog closes itself; the panels update, the
  announcer reads it ("shot 4. 9.3, shot a touch low": `Announcement.for_shot`,
  worded as the engine words a shot) and chatty mode comments. NO DOUBLE COUNT:
  the engine kept its baseline, so its camera check may still find that hole
  later - an engine shot within `EngineEvent::TWIN_MM` (3 mm) of a shot plotted
  on that card in the last 15 min, found by the CAMERA (a new shot comes with a
  sound), updates the plotted shot instead of adding one. Camera-only sessions
  (no mic) could in theory merge a genuinely new shot within 3 mm of a plot.
- **Deleting a shot** (shot page, with a confirm; 2026-11-12): `Shot#remove!` -
  pictures and call go, and EVERYTHING after it renumbers (the shooter: "always
  renumber"): card numbers, and in a match / final the competition numbers, with
  a match's 10-shot series recounted (`Shot.series_for`; a final's series are
  timed windows and stay). New competition shots take `match_number` from the WEB
  APP's count, not the engine's, so a deletion leaves no gap (the engine matches
  events by `engine_shot_id`, so this is safe). Left as is: the ENGINE still
  counted the deleted shot, so in a live match its spoken "shot N" runs one
  ahead, and its "extra shot" penalty (a final's window over its count) may fire
  one shot early.
  Any card of a session has its own page, `/practice/:id/cards/:number`
  (`CardsController`; linked from "Earlier cards this session"; prev / next card):
  target, card numbers, and `ShotListComponent(deletable: true)` with a Delete on
  each row that comes back to the card (`back=card`). Not broadcast: a static page.
- **Continuing a session** (2026-11-12, the shooter's choices: stop, improve
  something, carry on in ONE session): "▶ Continue session" on a FINISHED
  PRACTICE session from TODAY (`PracticeSession#continuable?`; not a match or
  final - their clock and series can't resume). One click, same rig and gear:
  `EngineRunner.continue!` reopens the session (new run token, the engine log
  appended) and starts the engine with `--resume FILE` - the last card's number,
  its holes (target mm) and the last shot's after picture. The engine runs
  `_same_card` on its first baseline: same card -> keeps counting it toward 10
  and checks overlaps against its holes ("same card, ready"); else `new_card`
  ("new card, ready"). `break_seconds` (the time it stood finished) is left out
  of the report's duration (`shooting_seconds`).
- **Deleting a session** (list and range screen, with a confirm): cards, shots,
  calls, pictures (purged at once - `dependent: :purge`, no job worker needed) and
  the engine log go too. Refused while live (`before_destroy ..., prepend: true`,
  so it runs before the cards cascade); `reconcile!` first, so a dead engine's
  session can be deleted. Deleted calls are gone from the future training set.
- **Pickers list only what was found** (`DeviceChoice`, the wizard's steps):
  the last probe's cameras/mics + stream URL + camera only. No built-in device
  (the web app used to default to "Kiyo" / camera 0 and show them even when
  absent). Pre-select: last choice if still found (a URL always) > `SPOTTER_*` if
  found > camera's own mic / first camera > camera only. Start with nothing picked
  is refused. The engine has no built-in device either: `--mic` defaults to the
  computer's DEFAULT INPUT (`audio.find_input(None)`), `--device` to index 0.
  Careful: `str(None).lower() == "none"`, so camera-only is tested as
  `a.mic is not None and ...` - else no `--mic` silently meant camera only.
  Specs use `tmp/cameras-test`: they used to wipe the dev server's `tmp/cameras`.
- **The wizard's checks** (were the Rig setup page), both LIVE through
  `RigCheck::LiveProcess` (runs an engine command printing JSON lines, streams
  each to the user's page over Turbo; one rig check at a time, never in a
  session; state in-process, `RigCheck.reset!` between specs; `at_exit` stops running checks, else a check outlives a server restart holding the camera or mic for minutes with nothing able to stop it - verified). Camera check =
  `phase1.py locate --json --watch SECONDS --overlay PATH` (a result about once a
  second, ~0.6 s solve, overlay written atomically; `sharpness` = Laplacian
  variance as a focusing aid; verdicts in `RigCheck::CameraVerdict`, plain
  words; flatness warns 0.15-0.5 mm and only blocks "Ready to shoot" beyond 0.5,
  because real cards read 0.2-0.6 and still scored right, and a used card's holes
  read as bow); sound check = `phase1.py listen --json` (`RigCheck::Listen`):
  "level" lines 4x/s drive a meter redrawn on its own (`ListenMeterComponent`),
  each sound marked `would_trigger` from the engine's own `TRIGGER_DB`/`TRIGGER_MS`
  constants (shared with `shot --auto`'s defaults). Start stops the user's own
  checks first and refuses while anyone else's runs. VERIFIED in real Chrome against the dev server (Ferrum, no reload):
  countdown and meter update live - which also confirms the Turbo push path the
  range screen uses. Note: system specs can't see live updates (test cable
  adapter); drive a real browser for that.
- **Stop must work even with SIGINT inherited as IGNORED** (a process started
  in the background from a script; Python keeps an inherited ignore). The engine
  installs SIGINT and SIGTERM -> KeyboardInterrupt in `main()`
  (`_stop_signals`). Found when the demo task, started in the background, could
  not stop its engine; without the fix the web app's Stop would silently do
  nothing under any service manager. Verified with an inherited ignore.
- `bin/rails spotter:demo` replays the real 10-shot card 044-053 through the real
  engine (`camstream.py --playlist`, no mic) into a "Demo" user (`demo` / PIN 1010, or LOGIN=...),
  writing the engine's files to a temp `SPOTTER_OUT` so the real shot log is never
  touched. Default 10 s per image (>= 7 s enforced; 7 s lost shots while Spotlight
  indexing slowed solves 1.7x): camera-only needs two checks + scoring, and at 5 s
  two holes landed in one comparison and one was lost (6 of 10) - which is also
  the real limit for camera-only mode (no mic): shots < ~5 s apart can be missed.
- Browser specs: `spec/system` (Capybara + Cuprite, as fl-shooters) for screens
  request specs can't see; `SCREENSHOTS=1` saves tmp/screenshots/.
- **Proposal vs call:** a `Shot` keeps the rules' proposal (position, score, flags,
  every estimate, geometry health, frames, straightened close-ups) and the
  shooter's call (ring, decimal, TAPPED POSITION, note) in separate columns; their
  difference is the training label for the planned model that will replace the
  hand-written rules (fl-shooters stores proposal vs final holes the same way).
  Displayed scores go through `Shot#final_*` (the call wins).
- Close-ups are straightened top-down at 20 px/mm (`report.closeup`), so a tap is
  a position in target mm and the patches are uniform for training.
  The amber call circle is DRAGGED as in fl-shooters (`closeup_tap_controller.js`):
  grab keeps the grab offset (no jump), press elsewhere jumps then follows, arrows
  nudge 0.1 mm (Shift 1 mm); `touch-none` so dragging doesn't scroll on a phone.
  Verified in Chrome: drag (+60, +40) px moved it exactly that.
- `TargetSpec` (Ruby) and `shot_call_controller.js` re-implement `scoring.py`'s
  arithmetic; `spec/models/target_spec_spec.rb` pins the same values. Change all
  three together. Positions are mm, x right, **y UP** (fl-shooters stores y down).
- Time zone defaults to Eastern (`SPOTTER_TIME_ZONE` overrides).

- **Live camera view** on the range screen (2026-11): the engine holds the camera,
  so it serves it (`shot --auto --stream-port PORT`, `liveview.LiveView`, 127.0.0.1
  only): ~4 fps, 960 px, rings of the current baseline drawn on, encoded only when
  asked. `EngineRunner` picks a free port (`practice_sessions.stream_port`); the
  page polls `GET /practice/:id/camera` (relayed behind the login; 204 = no picture,
  410 = session over, picture removed). Polling snapshots rather than relaying
  MJPEG keeps no Puma thread open per viewer. The camera picture is outside
  everything `LiveBroadcast` replaces, else every shot would blank it; the panel
  is split into `live_target/latest/stats/list` for that reason. The header (status
  pill + Stop) is broadcast too, so Stop goes away when the session ends.
- **Guns and pellets** (2026-11-12, journal groundwork; the shooter's choices):
  `Gun` is ONE type (`kind` = TargetSpec key; can't change once it has sessions),
  `Pellet` is one row PER LOT (match shooters test/buy by lot). Both RETIRED, never
  deleted (`Retirable`), so old sessions keep them. A session's gun and pellets are
  OPTIONAL, pre-selected by `GearChoice` (last gun at this target; the pellets last
  used WITH THAT GUN), chosen on the wizard's Start step and editable on the session
  page (`SessionGearComponent`, outside `LiveBroadcast`). Pellets are typed in right
  there ("New pellets…") and remembered (`GearParams`, which also finds ids only
  through `Current.user`); "New lot of these" copies one so only the lot is typed.
  `practice_sessions.gun_adjustments` = what was changed on the gun that day (on
  the SESSION, not a log on the gun); the gun's page lists them as its history.
  Gear page: `/gear` ("Guns and pellets" in the menu).
- **Session diary** (2026-11-12, the shooter's choices): a Diary card on the session
  page, filled any time (`SessionDiaryComponent`, `PATCH /practice/:id/diary`,
  `DiaryParams`). Exercises = TAGS to tap (`Exercise` per user, `SessionExercise`
  join; typed once, offered after, most used first; a tag no session uses is
  deleted by `Exercise.tidy!`). Three boxes kept APART so the journal can list
  problems across sessions: `problems`, `fixes`, `learned`. NO location or weather:
  Spotter is an at-home rig (the shooter's call).
- **Journal** (`/journal`, 2026-11-12), built for the shooter's goal, the OLYMPIC
  TRIALS: pistol qualification is 60 shots in WHOLE rings, benchmark **565**
  (`Journal::DEFAULT_GOALS`; editable per target in `users.goals`, removable).
  `SessionSummary` per session: competition shots only, penalized = 0, call wins;
  score PER 60 (sessions under 10 shots aren't charted), complete 10-shot series
  (worst series matters most), 10s per 60, mean card group size. Charts are
  server SVG (`JournalChartComponent`, :line / :range; axis capped at the max
  possible, goal label in the right margin, hover = SVG title, the table is the
  data view). Filters (autosubmit): type, kind, gun, pellets, exercise, period.
  Decimal average deliberately NOT the headline (finals only; decimal accuracy
  is unverified). Headline tiles (the shooter is still FAR from 565, so
  progress, not pass/fail): recent pace (last 5), to goal + closing vs the 5
  before, trend per month + forecast date (least squares; only after 8 sessions
  over 2 weeks; no forecast unless climbing), personal best (date first set),
  worst recent series.
- **Shotmetrix QR export** (2026-11-12): `/practice/:id/shotmetrix`, from the
  session page's Export card. Open format (github.com/shotmetrix/Shotmetrix-QRCode,
  Apache-2.0, no API key/registration): `ShotmetrixCode` is a port of their Python
  reference encoder (X25519 + HKDF-SHA-256 + AES-256-GCM, Base32, always QR v24),
  verified BYTE FOR BYTE against their test vectors (copied to
  `spec/fixtures/files/shotmetrix/`). `ShotmetrixExport`: final values (call wins),
  pistol whole rings / rifle + finals decimals, sighters flagged, penalized = 0
  with NO position (else it fails their value-vs-position check, +-0.3 / +-1 ring),
  a call too far from its position is sent as the position's own value, >120 shots
  = several codes, id fixed per session+part (HMAC of secret_key_base) so a session
  imports once. Their check measures from the pellet CENTRE (ISSF gauge); ours is
  at most ~0.1 more generous - inside the tolerance. The name "Shotmetrix" may only
  describe that we produce their codes (their NOTICE).
- **Session report / PDF** (2026-11-12): `/practice/:id/report` (Export card),
  `layout "report"`: paper, LIGHT ONLY (no dark: classes), no app menu; "Save as
  PDF" = the browser's print dialog (`print_controller.js`), no PDF gem - targets
  stay vector. Header (shooter, gun, pellets + lot, duration, exercises), the
  session's numbers (`SessionSummary`, match total via `EventStats`), each card's
  target + shot table (`break-inside-avoid`), notes. JOURNAL report:
  `/journal/report` with the journal's filters (tiles, both charts with
  `paper: true`, sessions, notes); `Journal#tiles/score_points/series_points`
  are shared by page and report.
- **Scores shown as the session is scored** (the shooter, 2026-11-12: "78 (81.8)
  makes no sense"): `PracticeSession#whole_rings?` (pistol practice and matches =
  whole rings; rifle and finals = decimals) -> `CardStats#score/score_average`.
  Totals/averages never mix the two. Per-shot decimals still show per shot.
- **A FINISHED session opens on the whole session** (2026-11-12, the shooter's
  call, every kind of session): all competition shots on one target, numbered in
  firing order across cards (`TargetSvgComponent in_order:`; a match's own numbers
  win), `SessionResultComponent` (match/final total "of 60 shots" via EventStats,
  else whole rings for pistol / decimals; series with the worst outlined;
  sighters and out-of-time zeros noted; the session's group) and every card
  linking to its card page. LIVE is unchanged. When a session ends,
  `LiveBroadcast` sends a Turbo REFRESH instead of section replaces, so an open
  range screen reloads into the summary.
- The range screen sizes the target by window height (`LivePanelComponent::TARGET_SIZE`,
  `100svh - 7.5rem`, cap 60rem) so the whole card is visible without scrolling.
- **Range screen layout (2026-11-12, by the shooter's eye):** target ZOOMS
  (`TargetSvgComponent` `:fit`): framed on the black, out a WHOLE ring at a time only
  as far as the widest shot needs (live, per shot); ring numbers 1-8 on the axes as
  printed, only bands fully in view. Right column capped at 32rem, the pair centred
  (`#range_side`); the target is `lg:sticky` beside it. Column order: course panel
  (compact: clock + Start match, then one score line), latest shot (no heading; big
  decimal, an arrow at the shot's exact angle, then this card's shots as WHOLE rings,
  the call winning), camera (thin frame, no heading), stats, shot list. Must fit a
  1322x729 laptop window with the whole camera visible in a match (spec checks it).
  Colours shared by target and ring row: latest = amber ring, flagged = red,
  penalized = grey struck 0. Mic check: verdict + Next above the sounds, newest 5
  shown, the rest in a `<details>`.

Not built yet: see "Where we left off" for the agreed order.

## Announcer voice: Kokoro (2026-11)

The shooter rejected the Mac voices (incl. Premium) for **Kokoro** (kokoro-onnx,
Apache-2.0): 19 of its 28 English voices (the shooter dropped Jessica, Kore, River, Echo, Eric, Liam, Onyx, Puck and Lewis on 2026-11-12), each USER picks theirs.

Built and committed:
- `engine/voicelines.py` (pure Python, shared): `VOICES` (19 ids), `split(text)`
  -> sentences -> pieces, `pieces()` = every piece the engine can say (~300:
  "shot 1".."shot 60", "0.0".."10.9", direction phrases, flags, fixed lines,
  "that's N", the range officer's commands from `course.phrases()`),
  `SENTENCE_GAP_S` 0.55 / `COMMA_GAP_S` 0.25. **The shooter wants clear PAUSES
  between statements** (run-together phrases are hard to take in while shooting):
  each piece is rendered alone and joined with real silence, never one long text.
- **Wording the shooter chose (2026-11-11), by ear:** a single word rendered as
  its own piece sounds wrong ("check.", "low."), so: no spoken "check" on a
  flagged shot (the check TONE marks it; score first, then why: "shot 4. 9.0,
  shot a touch low. line call"), and the direction is one piece "shot [degree]
  <dir>", degree by ring so pistol and rifle match: "a touch" 10-9, plain 8-7,
  "well" 6 or worse (`phase1._spoken_direction`, `voicelines.DIRECTION_PHRASES`).
  Inner ten stays "center, inner ten". End of card: "that's 10. new card please"
  (not "10 shots, change the card"). When Rails takes over the announcement
  (below), it must build the same text.
- `engine/voice/`: own **Python 3.13** venv (Kokoro's onnxruntime/scipy have no
  Python 3.15 builds; the engine venv is 3.15). `brew install python@3.13 &&
  engine/voice/setup.sh` (venv + ~350 MB model, both gitignored with `cache/`).
  `speak.py serve|prewarm|sample|samples|say|list`; pieces cached per voice in
  `cache/<voice>/pieces/*.wav` (~1.3 s a piece on the old laptop; the 2026-11-11
  laptop rendered all 28 samples in ~2 min). The cache is keyed by the piece's
  TEXT: any wording change needs the samples rebuilt (`rm cache/*/sample.wav &&
  speak.py samples`); stale pieces are just unused.
- **The BROWSER plays the announcements** (2026-11-12, built): web-started
  sessions run the engine with `--announce web` (no `--voice`): `say()` in
  `phase1.py` takes (phrase, diagnostic) parts and, instead of speaking, emits
  an `announce` event - sentences of voicelines pieces, each marked
  `diagnostic`, `kind` / `plain_kind` (tone with / without the diagnostic
  parts; null = silent then), the gaps (docs/engine-events.md). RO pacing uses
  `_WebSpeech` (an estimated end; the engine can't hear the browser).
  `Announcement` (Rails) drops diagnostic sentences unless
  `users.diagnostic_announcements` (Settings, "What the announcer says"; off by
  default) and Turbo-APPENDS it to `#announcements`; `announcement_controller.js`
  hands it to `announcer_controller.js` (`AnnouncerComponent`, the Sound button
  beside Stop - outside every broadcast part; ON BY DEFAULT, turned off it is
  remembered per device in localStorage; browsers play only after a tap or key
  press on the page - arriving via the app's own Start usually counts (Turbo keeps
  the document), else "Tap anywhere for sound" and the first tap/key anywhere
  starts it, keeping only the latest announcement meanwhile): one at a time, a
  WebAudio tone (made in JS - no Apple sound files in a public repo; none for
  "ro"), then each piece fetched from `GET /voices/:id/piece?text=` and
  scheduled gap-exact. No Kokoro on the server -> the browser's own voice.
  Terminal runs (`--announce local`, default) still speak through `_announce`
  / `KokoroVoice` / `say`, ALL parts.
- **Diagnostic mode** (the shooter: "only the shot number, the score and
  direction"): OFF says lead + score + direction (+ inner ten), the match facts
  (sighter, "out of time, scores zero") and the end of card; ON adds line call,
  ring uncertain, overlaps a hole, rough hole, found without a sound, view
  moving, geometry warning. Every other line (ready, card off, new card, not
  scored, camera lost, the RO) is always said.
- **Known pieces are IN GIT; anything new is rendered on first use** (the
  shooter, 2026-11-12: generate what we KNOW we need ahead, like the samples).
  `speak.py export --all` renders every `voicelines.pieces()` (~300: numbers,
  "shot N", directions, flags, fixed lines, the RO's commands) for all 19 voices
  as 32 kbps AAC into **`web/public/voice-pieces/<voice>/<slug>.m4a`** (DONE
  2026-11-12: 298 pieces x 19 voices = 5,662 files, 65 MB (28 voices took ~2 h on the old
  laptop); re-run after a wording change: only new pieces render, pieces no
  longer said are removed). Without Kokoro on a machine, an announcement whose
  pieces are all exported still plays in the voice (`Announcement#payload`
  `kokoro`); only then does the browser's own voice stand in. `Voice.piece_url` points the browser at
  that static file; a piece outside the set (future personality lines) goes to
  `GET /voices/:id/piece` -> `Voice.piece!` -> `speak.py piece` (~1-5 s once,
  then cached in `web/storage/voices/`, gitignored). `Voice.prewarm!` at session
  start renders only what is neither exported nor cached. Personalities plan:
  pick variations only among pieces already available, render the rest in the
  background, so the announcer never waits.
- **Chatty mode = live COMMENTARY** (2026-11-12, the shooter's design; WRITTEN
  RULES with many phrasings, not AI): `users.chatty` (Settings, and the range
  screen's "💬 Chatty / Quiet" button - a JSON PATCH, no page load, since a load
  turns Sound off). `Commentary` (Rails) runs after each engine event
  (`EngineEvent#apply!` -> `Commentary.after_event`), competition shots only,
  scored as the session is:
  after a shot AT MOST ONE remark, in priority order - 3+ tens in a row, 5 or 10
  in a row in the nine or better, three in a row on one side (+ advice), a flyer
  (> 2.5x mean radius from the group), a 7 or worse, an inner ten; every 10
  shots a SUMMARY (card / series total, best today or personal best or up/down
  on the last);
  a match also "halfway" + total at 30 and "last series" at 50; when the RO's
  phase is "done", the MATCH SUMMARY (final score, best series).
  The JOURNAL GOAL (565) IS NEVER SPOKEN - no pace, no "short of" (the shooter,
  2026-11-12: it is so far off that hearing the gap is demoralizing; the
  journal page still shows it). Lines: `config/commentary/default.yml` (a
  PERSONALITY = another file like it; `say` never repeats the last phrasing,
  via Rails.cache). Delivered as an Announcement of kind "chat" (no tone).
  `Commentary.pieces(user)` = every line with numbers filled in, pre-rendered at
  session start (`Voice.prewarm!(extra:)` -> `speak.py prewarm --extra FILE`).
  IN THE GIT EXPORT for af_bella, af_nicole, af_heart and am_michael (2026-11-12, the shooter's picks):
  `bin/rails voices:chatty_list` writes the list (default goal, 565) to
  `web/public/voice-pieces/chatty.txt`; `speak.py export --chatty --voice V`
  renders it; a plain `export` never removes a piece on that list. A user goal
  other than 565 renders its few goal pieces on first use. The page's end-of-session Turbo refresh WAITS until
  the announcer is idle (`turbo:before-stream-render`), so the match summary
  isn't cut off. Verified: spec/models/commentary_spec.rb, a real demo run.
  Not yet: personalities to choose from; qualifying-place remarks (needs other
  shooters' scores).
- **The 19 picker samples ARE in git**: `web/public/voice-samples/<voice>.m4a`
  (32 kbps AAC via macOS `afconvert`, 1.6 MB total; the shooter chose 32 kbps by
  ear), so a fresh clone can audition every voice without Kokoro.
  `speak.py samples` rebuilds them (and `SPOTTER_VOICE_SAMPLES`). Measured: all
  ~300 pieces x 28 voices would be ~370 MB as WAV, ~71 MB as 32 kbps AAC.
- Web: `users.voice`, `Voice` model (mirrors VOICES; `voice_spec` checks they
  match), Settings "Announcer voice" picker (`VoicePickerComponent`).
- Verified 2026-11-12: real engine + dev server (`spotter:demo`): 33 announce
  events accepted; real Chrome (spec/system/announcer_spec.rb): Sound on ->
  pieces fetched, decoded, played in order. NOT yet heard by the shooter.
- Open: the `--speaker` mic mute assumed the engine plays the sound; with the
  browser it can't know (off by default: earbuds). After a shot is DELETED in a
  live match, the engine's spoken "shot N" runs one ahead (it still counted it).

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
- **The Pi stream is SET UP (2026-11-12, `pi/README.md`):** Pi 3 hostname
  `spotter`, `spotter-camera.service` runs ustreamer on boot; the app's camera
  step takes `http://spotter.local:8080/stream`. Measured 1080p MJPEG at 7-8 fps,
  ~22.5 Mbit/s. Focus LOCKED at 187 (swept); exposure / WB / sharpness stay AUTO
  (manual exposure is broken on the Kiyo - see pi/README.md); trigger = the laptop's
  mic (gun). Jitter with this: ~1 um centre, ~2-3 um scale.
- Still to do on the Pi: measure the latency from the Pi 3.

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
- **A dark surround that RINGS the whole card is not the aiming mark**
  (2026-11-12, the Pi rig): its outer contour encloses the card, so it passed
  the fill and roundness tests, and as the largest dark region it won whenever
  its hull had 5+ points - a few pixels in a corner decided between a perfect
  fit and none. `find_target_frame` now rejects any region touching the
  picture's edge (a clipped mark could not be fitted anyway); selftest
  `test_dark_surround` reproduces it (fails without the rule, 64 px off).
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
- **Every BASELINE is verified** (2026-11-12, camera moved BELOW the card, ~30 deg,
  looking up: the baseline taken as a card went up fitted badly - inner rings
  drawn low and squashed for the whole card, on the live view and in the camera
  check - while frames a moment later fitted all 10 rings to 0.08 mm). `baseline()`
  in `_shot_auto` (session start, after movement, card back, re-find) tries up to
  5 frames and keeps the first `_fit_ok` one (perspective model, <= 0.4 mm,
  >= 1000 ring points; set on all 328 saved frames: genuine <= 0.32 mm from >=
  3071 points, misfits 0-132 points / no perspective), else the best. After a
  shot, an after frame that fits poorly also uses the baseline's geometry.
- **"⌖ Re-find target"** (range screen, beside Stop; the shooter bumps the camera
  sometimes): `EngineRunner.refind!` -> SIGUSR2 -> the engine takes a new verified
  baseline from the card as it sits now and says "ready". Only sent to an engine
  whose log says "re-find target: SIGUSR2" (an older one DIES of SIGUSR2). A shot
  fired since the last baseline and not yet scored would be absorbed - between
  shots only.
- **A hole on the aiming mark's RIM can misfit the after frame** (2026-11-12:
  two shots ~27 mm out, the black ends at 29.75): the after frame solved 63-69 mm
  off at ~-88% scale, the frames then read 45% "changed", the movement guard
  rejected the shot ("not scored, view moving") and the camera check scored it
  seconds later - the shooter heard "not scored", a pause, then the score.
  `score_now` now checks `_same_view(tf_after, tf_baseline)` (15 mm / 15%; all
  144 real pairs differ by <= 4.2 mm / 4%) and on a misfit uses the BASELINE's
  geometry (the camera can't move in a second; real movement still shows under
  it) - both shots then scored within 0.1 mm of the later scores. The camera
  check's own `locate` is unchanged (a misfit there must repeat twice to count).
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
- **The laptop mic at the firing line (the Pi setup, 2026-11-12)** hears the GUN:
  20 shots +67 to +74 dB; cocking, loading and coughs +46 to +57 (all ">= 180 ms"
  enough to pass), other sounds to +59.7, a card change +63.6. `TRIGGER_DB` is
  now **62** (was 45, for the Kiyo hearing impacts as quiet as +48.5 - use
  `--trigger-db 45` with that mic). "Not scored" is NEVER SPOKEN any more (the
  shooter: false triggers made it annoying); still logged and reported.
- **The Pi stream lags 0.2-1.6 s** (ustreamer's X-Timestamp vs arrival), so the
  first capture after a sound could show the card BEFORE the pellet: in one
  session 13 of 20 shots read "no new hole" and the camera check found them
  seconds later. After a SOUND with no hole yet, `score_now` looks again
  (`LATE_LOOKS` 3 x `LATE_LOOK_S` 0.6 s; movement still guarded). Verified with
  a fake mic + a hole shown 1.4 s late: old code "not scored", new code scored.
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
  `--frames` now DEFAULTS TO 1 (was 8, 2026-11-12): over the Pi's Wi-Fi only
  ~4 fps reach the laptop, so waiting for 8 new frames cost 2-3 s on every
  shot (1 frame: 0.24 s). Each viewer of `spotter.local:8080` shares that
  bandwidth - close ustreamer's page in the browser during a session.
- Lighting is currently front-lit with glare. Backlighting is better: the air
  rifle target's whole high-value area is black paper, where a hole is
  invisible under front light. Backlit, a hole is bright on a dark field.
- Not yet built: CSV export, announcer personalities, piezo auto-trigger,
  Raspberry Pi deployment (see "Where we left off"; the journal, reports,
  Shotmetrix export and the browser announcer are built).

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
