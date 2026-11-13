# Engine → web events

The spotter engine (`engine/phase1.py shot --auto --report-to URL`) reports everything it
does to the web app (`web/`) as it happens. This file is the contract between them.

The web app starts the engine itself when a signed-in user presses Start
(`web/app/models/engine_runner.rb`): it creates the practice session first, then
runs the engine with `--session-id <its id>` and `SPOTTER_TOKEN=<that session's
one-time run token>`.

## Transport

`POST {URL}/api/events`, `multipart/form-data`:

| part | |
|---|---|
| `event` | JSON (below) |
| `before_image`, `after_image` | full frames, PNG (shot and unscored events) |
| `closeup_before`, `closeup_after` | straightened close-ups, JPEG (shot events) |

Auth: every event must name a session the web app created (`session_id`) and send
`Authorization: Bearer <that session's run token>` (the engine sends
`SPOTTER_TOKEN`). Anything else is 401: an engine can only write into the session
it was started for.

The engine posts from a background thread and never lets the web app slow or stop
scoring: if the web app is down, events are logged and dropped, and the shot log
(`engine/out/shots/calls.csv`) and frames on disk remain the record.

**Two lanes** (2026-11-12): the engine sends events WITH pictures (`shot_images`,
`unscored`) in one queue, in order, and everything else in another, at once - so
an announcement or a score never waits behind seconds of picture encoding and
upload. Across the lanes, order is not guaranteed: pictures can arrive after
later events.

## Event JSON

```json
{ "type": "shot", "session_id": "20261111-153102-4f2a", "at": "2026-11-11T15:31:10.412Z", "data": { } }
```

`session_id` is the web app's id for the session (`--session-id`); an engine run
by hand without it makes its own, which the web app will refuse. `at` is when it happened (for a
shot: the impact). Positions are **millimetres from the target centre, x right,
y UP**.

| type | data |
|---|---|
| `session_started` | `target` ("pistol" / "rifle"), `rule` ("pellet" / "visible" / "gauge"), `course` (null = practice, or "match" / "final" / "ranking") |
| `ready` | — |
| `card_off` | — |
| `new_card` | — |
| `shot` | see below. Sent WITHOUT pictures, at once |
| `shot_images` | `engine_shot_id`; the shot's pictures (`before_image`, `after_image`, `closeup_before`, `closeup_after`), sent after it. Attached to that shot; no broadcast |
| `unscored` | `reason`, `trigger`, `engine_shot_id` (optional) |
| `session_ended` | — |
| `announce` | only with `--announce web` (sessions the web app starts): what the engine would say, for the web app to play in the browser. `kind` (tone: "ok" / "check" / "fail" / "ready" / "info" / "ro"), `plain_kind` (the tone when diagnostic sentences are left out; null = say nothing then), `sentences` [{`pieces` [normalized voice pieces, voicelines.split], `diagnostic` (true: line call, overlaps, found without a sound... - said only in diagnostic mode)}], `gaps` {`sentence`, `comma`} seconds of silence |
| `course` | the range officer's latest call (match / final only): `phase` ("command" / "window" / "pause" / "done"), `label` (the command said, or "Sighting" / "Match" / "Series 2" / "Shot 13"), `ends_at` (ISO time the window or pause ends), and for a window `stage` ("sighting" / "match"), `shots` (allowed, or null), `skippable` |

`shot`:

| field | |
|---|---|
| `engine_shot_id` | the engine's log number ("044") |
| `trigger` | `sound` / `camera` / `final_check` / `sound_camera` (a sound whose capture was too early, then the camera check found it within 20 s: heard AND seen; `at` = the sound) |
| `sound_db` | loudness over the room floor, when triggered by sound (also `sound_camera`) |
| `detect_s` | seconds from the sound to the score (`sound` / `sound_camera`; null for a camera find) |
| `x_mm`, `y_mm`, `r_mm` | scored position (the rule's choice of estimate) |
| `decimal`, `ring`, `inner_ten` | the rule's score (decimals truncated) |
| `rule`, `line_mm`, `line_call`, `ambiguous`, `overlap` | how it was scored, and its flags |
| `estimates` | every position estimate: `centroid` [x,y], `circle_fit` {x,y,ok,arc_deg}, `visible_edge_r_mm`, and `closeup` {centre: [x,y], px_per_mm, size_px} |
| `region` | detected region: `dia_mm`, `circularity`, `peak` |
| `geometry` | `ring_rms_mm`, `perspective`, `k1`, `k2` |
| `course` | null in practice; in a match or final: `stage` ("sighter" / "match"), `label`, and for a match shot `series`, `number` (in the event) and `penalty` (null, "out of time", "after the end", "extra shot": scores zero) |

Courses of fire live in `engine/course.py` (`web/app/models/course.rb` mirrors
their names and shot counts; its spec checks they agree). The web app starts the
engine with `--course KEY`; "Start match" sends the engine SIGUSR1, which ends a
match's sighting time early.

The close-ups are top-down (perspective and lens removed), `px_per_mm` pixels per
millimetre, `size_px` square, centred on `closeup.centre`: pixel (u, v) is
x = cx + (u - size/2) / px_per_mm, y = cy - (v - size/2) / px_per_mm.
