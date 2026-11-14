# spotter web

The range screen and shot review for the spotter engine (the Python app in
`../engine`). Rails 8.1 · Ruby 4.0 · SQLite · Hotwire · Tailwind v4 · ViewComponent · RSpec,
following fl-shooters' conventions (its button, card and base components and colour
palette are copied from there).

## Run it

```bash
cd web && bin/dev            # http://localhost:3000
```

Sign up (open sign-up; each shooter sees only their own sessions), then press
**New session** on the Practice page and go through the setup wizard (below);
its last step, **Start session**, launches the engine
(`EngineRunner`, from `../engine` with its `.venv`) and the range screen updates
live as you shoot. **Stop** is Ctrl+C for the engine: it makes a last check for an
unscored hole, then ends the session. One session at a time (one camera): while
someone shoots, Practice says who. If the engine dies (no camera, no mic), the range
screen shows the last lines it printed.

The range screen fits the whole card in the window, and while the session runs it
shows a **live camera picture** with the fitted rings drawn on. The engine holds
the camera, so it serves the picture (`--stream-port`, 127.0.0.1 only, on a free
port `EngineRunner` picks). The page fetches it a few times a second through
`GET /practice/:id/camera`, which relays it behind the login, so it also works
from a phone.

The wizard's pickers list **only the cameras and microphones the last device
search found** (`DeviceChoice`), plus a stream URL and camera only. Nothing is built in: a remembered device that isn't there now is
not offered.

The rig, set in the environment of `bin/dev`:

| | default | |
|---|---|---|
| `SPOTTER_CAMERA` | none | optional rig camera (index or the Pi's stream URL), pre-selected only if the device search finds it (a URL always) |
| `SPOTTER_MIC` | none | optional rig microphone name, pre-selected only if the device search finds it |
| `SPOTTER_ENGINE_DIR` | `../engine` | where `phase1.py` and `.venv` are |
| `SPOTTER_WEB_URL` | `http://127.0.0.1:$PORT` | where the engine posts its events |
| `SPOTTER_TIME_ZONE` | Eastern | shown times |

**New session** runs a setup wizard every time (`SessionSetupController`,
`/practice/new/...`), so the camera and microphone are known good before the
first shot:

1. *Camera*: pressing New session runs the engine's `cameras.py --json` (~5 s)
   and shows a preview picture from each camera, so you pick the one pointed at
   the target by what it sees (macOS's names are only a hint: their order doesn't
   always match the camera numbers), or a stream URL; and the target. "Look
   again" searches again. A new camera brings its own microphone (Kiyo with
   Kiyo, iPhone with iPhone) when there is one.
2. *Camera check*, live: the engine's `locate --json --watch` re-checks about
   once a second for two minutes, and the page updates the view with the fitted
   rings, a sharpness number (turn the focus for the highest) and plain verdicts
   (focus, ring fit, framing, distance, flatness, light) as you aim and focus.
   **Next unlocks at "Ready to shoot"**; "Continue anyway" is the escape.
3. *Microphone*, the sound check: `listen --json` shows a live level meter
   against the trigger level (with "measuring the room" and a countdown), and
   each sound as it happens, marked "would trigger" against the engine's own
   settings (`TRIGGER_DB` / `TRIGGER_MS` in `phase1.py`). **Next unlocks once a
   sound would trigger**; "No microphone - camera only" is the escape: the
   engine runs with `--mic none` and finds each shot with its 2-second camera
   check instead of the shot's sound.
4. *Start*: what was chosen and whether each check passed, **Practice, Match or
   Final** (two final formats), shots per card, then Start session. In a match or
   final the engine's virtual range officer (`engine/course.py`) calls every
   command and the range screen shows its clock and the event score; "Start
   match" ends a match's sighting time early; shots out of time score zero.

Each step stops the previous step's check, so the camera and microphone are free
for the next; neither check runs during a session.

**Settings** holds the *announcer*: each shooter picks one of 19 Kokoro voices
(play buttons for a sample of real announcements; `public/voice-samples`), turns
*diagnostic mode* on or off (off: after a shot only its number, score and
direction; on: also line calls, overlaps, shots found without a sound...) and
*chatty mode* (commentary: streaks, bests, patterns, a summary every 10
shots and after a match; also a button on the range screen). The range screen
plays the announcements in the browser (tap "Sound off" once per visit). Every
piece the engine says is in git (`public/voice-pieces`, all 19 voices); chatty
mode's lines (`config/commentary/default.yml`) are rendered on first use and
cached in `storage/voices`, which needs `../engine/voice/setup.sh` once; without
it, those lines use the browser's own voice.

Start `bin/dev` from a terminal that has macOS camera and microphone permission:
the engine inherits it.

Shooters sign in with a **username and a 4-8 digit PIN**; the email address is
stored but not used to sign in. Forgotten PIN (the app sends no email):
`bin/rails users:reset_pin LOGIN=<username> PIN=...` (`LOGIN`, not `USERNAME`,
which some shells set themselves).

To see it work without a camera or a gun: with `bin/dev` running,
`bin/rails spotter:demo` replays a real ten-shot card (engine/out/shots/demo, in git)
through the real engine - open the link it prints (sign in as
`demo`, PIN `1010`, or pass `LOGIN=<your username>` to use your own account) and watch the range screen fill up live. Its shots go to a temporary
folder, never the real shot log.

To test without a camera: `cd ../engine && ./.venv/bin/python camstream.py
--image out/shots/demo/053_after.png --port 8090`, then `SPOTTER_CAMERA=http://127.0.0.1:8090/stream
SPOTTER_MIC=MacBook bin/dev`.

From another device on the same Wi-Fi: put `SPOTTER_BIND=0.0.0.0` in `web/.env`, run
`bin/dev` and open `http://<this Mac>.local:3000`. For the range screen's MICROPHONE
(the browser as the shot trigger) the page must be https: run `bin/rails spotter:tls`
once, restart `bin/dev`, trust `storage/tls/spotter-ca.pem` on that device
(macOS: open it, Keychain Access > "Spotter local CA" > Trust > Always Trust), and open
`https://<this Mac>.local:3443`. Anyone on that network can then see
and change calls - fine at home, think twice elsewhere. The events API only accepts an engine the web app started (each session's own
run token).

## What's where

| | |
|---|---|
| `User`, `Session`, `Current` | Rails 8 authentication; open sign-up (`RegistrationsController`) |
| `EngineRunner` | starts / stops the engine for a user, one session at a time, notices a dead engine |
| `SessionSetupController`, `WizardStepsComponent` | the new-session setup wizard |
| `RigCheck::Locate`, `RigCheck::Listen` | the wizard's camera and sound checks |
| `EngineEvent` | applies one engine event (contract: `../docs/engine-events.md`) |
| `LiveBroadcast` | pushes a session's header (status, Stop) and live sections (target, latest, stats, list) to open screens; never the camera picture, which refreshes itself (`LiveCameraComponent`, `live_camera_controller.js`) |
| `PracticeSession` → `Card` → `Shot` | the data; a shot keeps the rules' PROPOSAL and the shooter's CALL in separate columns |
| `TargetSpec` | ISSF ring geometry and scoring, a port of the engine's `scoring.py` (specs pin the same values) |
| `CardStats` | total, average, inner tens, group size, group centre, mean radius, time per shot |
| `TargetSvgComponent` | the target drawn server-side as SVG, in mm |
| `Voice` + `VoicePickerComponent` + `voice_preview_controller.js` | the announcer voices (mirrors `engine/voicelines.py`), Settings' picker and sample player |
| `ShotReview` | walking a session's shots to call them: "Save and next" visits every shot |
| `DeviceChoice` | what the camera / microphone pickers offer: only what the last search found |
| `CloseupComponent` + `closeup_tap_controller.js` | straightened close-ups; a tap is a position label in mm |

## The data is the training set

Every shot keeps what the rules proposed (position, score, flags, every estimate,
the geometry's health, before/after frames and straightened close-ups at
20 px/mm) separately from the shooter's call (ring, optional decimal, the tapped
position, a note). Their difference is the label for the planned model that
replaces the hand-written rules - so review every session, and tap the position
when you can: it is the most precise label.

## Tests

```bash
bundle exec rspec                      # includes spec/system (Capybara + Cuprite: needs Chrome)
SCREENSHOTS=1 bundle exec rspec spec/system   # also saves tmp/screenshots/*.png
bin/rubocop
```
