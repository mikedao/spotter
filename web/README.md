# spotter web

The range screen and shot review for the spotter engine (the Python app in
`../engine`). Rails 8.1 · Ruby 4.0 · SQLite · Hotwire · Tailwind v4 · ViewComponent · RSpec,
following fl-shooters' conventions (its button, card and base components and colour
palette are copied from there).

## Run it

Two terminals, from the repo root:

```bash
cd web && bin/dev                                   # http://localhost:3000
cd engine && ./.venv/bin/python phase1.py shot --auto --per-card 10 --report-to http://localhost:3000
```

Open http://localhost:3000. A session appears as soon as the engine starts, and
updates live as you shoot (Turbo Streams; nothing to refresh).

From your phone on the same Wi-Fi: start the web app with
`bin/rails server -b 0.0.0.0` (plus `bin/rails tailwindcss:watch` if editing styles)
and open `http://<laptop's address>:3000`. Anyone on that network can then see
and change calls - fine at home, think twice elsewhere. The events API still only
accepts the engine on this machine unless `SPOTTER_TOKEN` is set (then the
engine must send it, and does when the same variable is set in its shell).

## What's where

| | |
|---|---|
| `EngineEvent` | applies one engine event (contract: `../docs/engine-events.md`) |
| `LiveBroadcast` | pushes a session's status line and live panel to open screens |
| `PracticeSession` → `Card` → `Shot` | the data; a shot keeps the rules' PROPOSAL and the shooter's CALL in separate columns |
| `TargetSpec` | ISSF ring geometry and scoring, a port of the engine's `scoring.py` (specs pin the same values) |
| `CardStats` | total, average, inner tens, group size, group centre, mean radius, time per shot |
| `TargetSvgComponent` | the target drawn server-side as SVG, in mm |
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
bundle exec rspec
bin/rubocop
```
