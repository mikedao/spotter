# Building your own rig

This guide is for building a spotter at home: a webcam pointed at a paper
target, a laptop that runs the software, and (optionally) a microphone that
hears your shots. There are no custom electronics and no soldering.

By the end you will have a rig that passes the app's camera check, hears your
shots (or finds them by camera alone), and scores a real card.

**What to expect.** Ring scores match a careful shooter's own call about 9 times
in 10. The misses are shots on a line, and those are flagged so you decide them.
The limits come from the paper (torn holes, a card that isn't flat),
not from the camera; see "Measured performance" in the [README](../README.md).

## Pick a rig

The camera has to be at the target, 10 m from you. The question is where the
laptop goes and how the picture gets to it. There are four ways, from the
least to buy to the most to set up:

| | **A. Laptop at the target** | **B. + phone or tablet** | **C. Long USB cable** | **D. Raspberry Pi** |
|---|---|---|---|---|
| At the target | webcam + laptop | webcam + laptop | webcam | webcam + Pi 3 + power bank |
| At the firing line | nothing | phone or tablet | laptop | laptop |
| Picture travels | USB, short | USB, short | USB, 10 m+ active cable | Wi-Fi |
| Shot heard by | a mic at the target | a mic at the target, or the phone's | the webcam's mic at the target, or the laptop's at the line | the laptop's mic at the line |
| You see scores | announced from the laptop; read them later | on the phone, announced in your earbuds | on the laptop | on the laptop |
| Extra to buy | nothing | nothing, if you have a phone | an active USB extension cable | a Pi 3, SD card, power bank |
| Status | works | works | **not tried yet** | the developer's rig |

Then follow the steps every rig shares, starting with
[Mount the camera](#1-mount-the-camera).

**What everyone needs:**

| | | notes |
|---|---|---|
| **Pellet trap** | your usual 10 m trap | Any trap that holds a 17 x 17 cm (pistol) or 8 x 8 cm (rifle) card flat. |
| **Webcam** | 1080p, sharp | Developed on a Razer Kiyo. Any webcam with a sharp 1920 x 1080 picture should do. |
| **Camera mount** | something rigid | A small tripod, a clamp, or a bracket near the trap. It must not sag or sway. |
| **Targets** | standard ISSF 10 m paper cards | Air pistol or air rifle. |
| **Backlight** | a white USB COB LED strip, e.g. [this one](https://www.amazon.com/dp/B0CDKVYPFN) | Lights the card from behind (see "Light it"). Strongly recommended. |
| **Diffuser** | a sheet of plain printer paper | Goes between the card and the light, to spread it evenly. |
| **Laptop** | a Mac or a Linux laptop | Runs the engine and the web app. |

---

## Rig A: laptop and webcam at the target

The bare minimum: the webcam plugs straight into the laptop, and both sit by
the trap. Nothing at the firing line but you.

```
 [trap + card] ◀── webcam ──USB── laptop  ))) announcer )))   ~10 m   you
```

**Where things go.** Put the laptop beside the trap, well **out of the line of
fire** and behind something solid. A pellet that misses the trap shouldn't be
able to reach it. Keep the cable tidy so changing cards doesn't snag it.

**Hearing shots.** At the target, the mic hears the **pellet hitting the trap**,
not the gun. That's good: coughs and cocking clicks at the firing line barely
register, and the hole already exists when the sound arrives. Use the webcam's
own mic if it has one (the app pairs it with the camera), or the laptop's.
Impacts are quieter than a gun at the firing line: expect about **+48 to +65 dB**
over the room's background. **Set the trigger level to around +45** in the
sound check. The default (+62) is for a mic at the firing line and would miss
most of your shots.

**Seeing scores.** You don't, while you shoot: you **hear** them. Leave the
range screen open on the laptop with Sound on and the volume up. The
announcer's voice reaches the mic too. That's harmless (a sound with no new
hole is ignored), but keep the volume no louder than you need. Read the range
screen when you walk up to change cards, and review the session afterwards.

You walk to the laptop to start, stop and pause. When that gets old, add a
phone (Rig B).

## Rig B: laptop at the target, phone or tablet at the firing line

Rig A plus the phone or tablet you already have. The laptop and webcam stay at
the target and do all the work; the phone at the firing line is the **range
screen**: scores, the live camera picture, the announcer in your earbuds, and
Start, Pause and Stop without walking downrange.

```
 [trap + card] ◀── webcam ──USB── laptop  ~ ~ Wi-Fi ~ ~ ▶  phone / tablet ── you
```

Set up the laptop as in Rig A. Then:

**Reach the laptop from the phone.** Answer `y` to the installer's phone
question (or run `./install.sh` again to). When Spotter starts, its window
shows the address to open on the phone, like `http://<laptop name>.local:3000`.
Both must be on the same Wi-Fi. Sign in on the phone and run the setup wizard
there: the camera previews come from the laptop.

**Hearing shots.** Pick one in the sound check:

- **A mic at the target** (the webcam's or the laptop's), as in Rig A, at
  about **+45**. Works over plain http.
- **The phone's own mic** ("This device's microphone", offered first): the
  range screen listens and hears your **gun**, loud and a metre away. Shots
  read about **+62 to +79 dB**; loading, cocking and coughs up to about +60.
  Set the level just under your quietest shot. A browser only lets a page use
  the mic over **https**, so this needs the one-time certificate set-up in
  [Watching from another device](#watching-from-another-device).

**Keep the range screen open and in front.** It plays the announcer and, with
the phone's mic, it *is* the trigger: switch to another app or let the screen
lock and both stop. (The page keeps the screen awake while it listens.) Any
shot missed meanwhile is still found by the camera, a few seconds late.

A tablet works the same way and shows a bigger target.

## Rig C: webcam at the target, long USB cable to the laptop

The laptop stays with you at the firing line and the webcam's USB cable runs
the 10 m to the target. You get the screen at your elbow and nothing
electronic downrange but the camera.

```
 [trap + card] ◀── webcam ════ active USB extension, 10-15 m ════ laptop ── you
```

> **Not tried yet.** Nothing in this rig is new to the software (it's a USB
> webcam like Rig A's), but nobody has run it over a long cable yet. If you do,
> please report how it went.

**The cable.** A plain USB 2.0 cable stops working past 5 m. Use an **active**
USB extension (a "repeater" cable, with a chip in each joint or at the end),
long enough for the run plus the walk around the trap: 10-15 m for a 10 m range.
A webcam's 1080p picture is a USB 2.0 stream, so a USB 2.0 active cable is
enough. Some longer cables need their own power at the far end. Run the cable
**along the floor or wall, outside the line of fire**, and tape it down where
you walk.

**Hearing shots.** Pick one in the sound check:

- **The webcam's own mic** (if it has one), now at the target: it hears the
  **impacts**, as in Rig A. Set the trigger level around **+45**. The app pairs
  a camera with its own mic automatically.
- **The laptop's mic** at the firing line: it hears the **gun**, loud and 1 m
  away. Shots read about **+62 to +79 dB**, while loading, cocking and coughs
  read up to about +60. Set the trigger level just under your quietest shot.

**Seeing scores.** The range screen is on the laptop in front of you, with the
announcer in its speakers or earbuds.

**Check the camera** (step 5) with the cable in place: if frames stutter or the
camera drops out, the cable is too long or under-powered.

## Rig D: webcam and Raspberry Pi at the target

A Raspberry Pi 3 at the target streams the webcam over Wi-Fi, and the laptop at
the firing line does everything else. Nothing crosses the range but a radio
signal. This is how the development rig runs.

```
 [trap + card] ◀── webcam ──USB── Pi 3 + power bank  ~ ~ Wi-Fi ~ ~ ▶  laptop ── you
```

**Extra parts.** A Raspberry Pi 3 (it only forwards the camera's picture, so a
Pi 3 is enough), a microSD card with Raspberry Pi OS, and a power bank. A Pi 3
runs off any ordinary USB power bank. A Pi 5 wouldn't: it needs 5 V / 5 A,
which power banks don't provide.

**Setting up the Pi.** Follow [pi/README.md](../pi/README.md): it installs
`ustreamer` as a service, so the stream starts when the Pi boots. In the setup
wizard, choose the camera by its stream URL: `http://spotter.local:8080/stream`.

The Pi has an advantage on a Mac: through the Pi you **can** lock the webcam's
focus (`v4l2-ctl`), which macOS doesn't allow. Do it once the camera is placed;
pi/README.md shows how to find the sharpest setting.

**Wi-Fi.** A 1080p stream is about 20-25 Mbit/s, close to what a Pi 3's 2.4 GHz
Wi-Fi manages. Keep the Pi in good range of the router. **Close ustreamer's own
page** in any browser during a session: every viewer shares the bandwidth.

**Hearing shots.** The Pi only sends pictures, so the **laptop's mic at the
firing line** hears the gun. Shots read about +62 to +79 dB. Set the trigger
level just under your quietest shot.

**Seeing scores.** On the laptop in front of you.

*Variant: a desktop runs it all.* If your laptop is slow, a desktop Mac on a
wired network can run the engine and web app, with the laptop at the firing
line only as a browser. The laptop's browser is then the range screen **and the
shot trigger**, which needs https (see [Watching from another
device](#watching-from-another-device)).

---

# Steps for every rig

## 1. Mount the camera

**Put it off to the side, out of the line of fire.** It doesn't have to look
at the card square-on. The software works out perspective and lens distortion
from the printed rings in every frame. It has been tested up to 45 degrees off
to the side, and the development rig runs at about 30-37 degrees. Beside the
trap, above it or below it all work.

- **Distance:** close, closer than you might expect. See
  [How far away](#how-far-away) below.
- **Rigid:** the software re-measures the card in every frame, so slow drift
  doesn't matter. A camera that *moves during a shot*, though, is
  rejected as movement. Don't mount it on the trap if the trap rings or
  shifts when hit.
- **Out of the way of your hands:** you will change cards often. A bump after
  a card change is fine (the next card gets a fresh measurement); a bump
  mid-card needs **Re-find target** on the range screen.
- **Focus:** focus once on the card and lock it, if you can. On Linux and on
  a Pi (Rig D), `v4l2-ctl` locks a webcam's focus (see
  [pi/README.md](../pi/README.md) for finding the sharpest setting). macOS
  can't lock it, so on a Mac autofocus stays on. It copes, because each
  picture is measured on its own.

### How far away

The card should nearly fill the picture **from top to bottom**: about 90% of
the height, with ring 1 completely in view. A 1080p picture is 1080 pixels tall,
so this puts about 5 pixels on every millimetre of card, which is what decimal
scoring needs. How far away that is depends on your webcam's field of view
(its spec sheet gives it, usually as a diagonal angle). Distances are measured
from the lens to the centre of the card, along the line of sight:

| webcam field of view (diagonal) | air pistol: aim for | air pistol: no farther than | air rifle: aim for |
|---|---|---|---|
| 65 degrees (narrow) | 30 cm | 43 cm | 14 cm |
| 78 degrees (typical, e.g. Logitech C920) | 24 cm | 34 cm | 11 cm |
| 82 degrees (Razer Kiyo) | 22 cm | 32 cm | 10-11 cm |
| 90 degrees (wide) | 19 cm | 28 cm | 9 cm |

"No farther than" is where the camera check's distance test stops passing
(0.25 mm per pixel). Beyond 0.32 mm per pixel it fails. The development rig's
Kiyo sits at about 25 cm and reads 0.20 mm per pixel. Use the table to start,
then let the camera check's **Distance** line decide.

**Off to the side, that is very close to the card.** At 22 cm and 35 degrees,
the lens is about 13 cm to the side of the card's centre and 18 cm in front of
it, only a few centimetres outside the card's edge. Make sure a wide shot can't
reach it: tuck it behind the trap's front frame or a small steel deflector, and
keep it out of the opening the pellets fly into.

**Air rifle** cards are small (8 cm), so the camera goes closer still: around
10 cm. Check that your webcam can **focus** that close (many can't below 10-20
cm), and that the camera check's Focus line passes. Rifle is supported, but
every real session so far has been air pistol.

## 2. Mount the card flat

Flatness matters more than anything else you control. Seen from the side, a
bump of height *h* moves the print by about *h* x tan(view angle). At 35
degrees, a 0.5 mm bump moves it 0.35 mm, nearly half a decimal on a pistol card.

- Clamp or pin all four edges. A holder that leaves one edge free lets it curl.
- **Cards curl.** If the camera check says "Slightly bowed" or "Not flat" in
  the same place on card after card, **turn the card 180 degrees**. On the
  development rig, that made a persistent bow in one corner go away.
- Judge flatness on a fresh card: holes in a used card read as bow.
- Up to about 0.5 mm of bow still scores correctly in practice (line calls
  are flagged anyway). Beyond that the camera check blocks "Ready to shoot".

## 3. Light it: backlight the card

**Light the card from behind.** It is the biggest single improvement you can
make to a rig.

### Why a backlight helps

The engine finds a shot by comparing a picture taken after it with one taken
before, and looking for **new light**: a place on the card that got brighter.
A backlight makes every hole exactly that, a bright spot of light coming
through the paper.

- **Holes in the black show.** Lit from the front, a hole in the black
  aiming mark is a dark hole in dark paper and is nearly invisible. Lit from
  behind, it's a bright spot on black, the easiest case there is. On a pistol
  card the black is rings 7 to 10, where most good shots land; on a rifle card
  the whole scoring area is black, so rifle all but needs a backlight.
- **Every hole looks the same.** A hole on white paper, black paper or a ring
  line reads the same way: light where there wasn't any. That makes holes
  easier to find and their centres easier to measure.
- **No glare.** Front light reflects off the paper, and a glossy patch can
  hide a hole or move around as the light or camera shifts. Light from
  behind doesn't reflect into the camera.
- **Steadier pictures.** With the card lit from behind, room lights and
  daylight matter much less, and the webcam's automatic exposure (which can't
  be locked on a Mac) has less to chase.

### Setting one up

You need two things: a **sheet of paper behind the card** that glows, and a
**strip of LEDs around the edge** that lights it.

```
   side view                       pellet ──▶
                                     │
   card ─────────────────────────────┼────────   ◀── camera sees this side
   gap 1-2 cm      LED strip ▶ ░░░░░░│░░░░░░ ◀ LED strip   (strip on the frame's
   diffuser (printer paper) ─────────┼────────          inside edges, shining
                                     ▼                  into the gap)
                                  trap
```

- **The light: a white COB LED strip,** e.g.
  [this one](https://www.amazon.com/dp/B0CDKVYPFN) (5 V USB, 5 W, 1 m,
  6500 K daylight white, 800 lumens, CRI > 90, self-adhesive). "COB" strips
  give a continuous line of light instead of separate dots, so the glow behind
  the card is even. At 5 W (1 A) it runs from any USB port: the laptop, a
  phone charger or a power bank. It has no switch and can't be dimmed: plug it
  in to turn it on. One metre goes around a pistol card's frame with some to
  spare.
- **Stick it around the inside edges of the trap's frame,** in the gap between
  the card and the diffuser, shining inward across the gap. On the edges it's
  out of the pellets' path: never put any light directly behind the card,
  where pellets go.
- **The diffuser: a sheet of plain printer paper 1-2 cm behind the card.** The
  strip lights it, the paper glows evenly, and every hole in the card shows as
  a bright spot against it. Pellets go through the diffuser too, so **replace
  it often**: a hole in the diffuser that lines up with a hole in the card
  shows as a dark patch.
- **Not too bright.** The camera check fails a picture with more than 0.5%
  blown out to white. The strip can't be dimmed, so if that happens, move the
  diffuser back a little, put a second sheet of paper over the first, or run
  the strip along fewer edges of the frame.

### Front light, if you must

Front light works on white paper, but not in the black, and glare is the
enemy: use diffuse light from the side, never a bare bulb near the camera's
line of sight. The camera check warns when the picture is dark (average under
35 of 255).

**Either way, keep the light steady.** Make one stable light the strongest on
the card, and turn off flickering or changing lights near the target. A
webcam's built-in ring light makes no difference to the card.

## 4. Install the software

Spotter runs on the laptop: a Mac, or a Linux laptop (Debian, Ubuntu and
their relatives). An installer sets up everything it needs.

**1. Open a terminal.** On a Mac: Finder > Applications > Utilities >
Terminal. On Linux: Ctrl+Alt+T.

**2. Paste these three lines** and press Return:

```bash
git clone https://github.com/mikedao/spotter.git ~/spotter
cd ~/spotter
./install.sh
```

On a Mac without developer tools, the first line opens a window offering to
install them: click Install, wait for it to finish, then paste the lines again.

The installer takes **10-20 minutes the first time** (most of it building
Ruby). It asks for your password when it installs system software, and at the
end it asks whether you'll use a phone or tablet as the range screen (Rig B):
answer `y` if so. If anything goes wrong it stops and says why. Fix that and
run `./install.sh` again: it picks up where it left off, and it's safe to run
any time (after an update, for example).

### Starting Spotter

- **Mac:** open the `spotter` folder in your home folder (Finder > Go >
  Home) and double-click **Start Spotter.command**.
- **Linux:** **Spotter** in your applications menu, or `~/spotter/start-spotter`
  in a terminal.

A window opens, starts Spotter and opens it in your browser. **Keep that
window open while you shoot.** To stop Spotter, close the window (or press
Ctrl+C in it). If a session is still running, it is stopped properly first.

**The first time:**

- **Mac:** macOS asks whether Terminal may use the camera and the microphone.
  Allow both, then quit Terminal completely (Terminal > Quit Terminal, or
  Cmd+Q) and start Spotter again. If you missed the question, turn both on in
  System Settings > Privacy & Security > Camera (and > Microphone).
- **Linux:** log out and back in once after installing, so you have access to
  the camera and microphone.

Then sign up in the browser (a username and a 4-8 digit PIN).

**Try it before you touch the rig.** With Spotter running, open a second
terminal window and run:

```bash
cd ~/spotter/web && bin/rails spotter:demo
```

It replays a real ten-shot card through the real engine. Sign in as `demo`,
PIN `1010`, and watch the range screen fill in.

The announcer's voices are already included, so the range screen talks with no
extra setup.

### Watching from another device

For Rig B's phone or tablet, or any second screen. If you answered `y` to the
installer's phone question, this is already done; to do it later, run
`./install.sh` again and answer `y`. The window that starts Spotter then shows
the address to open on the phone (on the same Wi-Fi), something like
`http://<laptop name>.local:3000`. Anyone on your network can reach the app
this way. That's fine at home.

For that device's **microphone** to be the shot trigger (Rig B, or the Rig D
variant), the page must be https. The installer has made a certificate for
that (by hand: `bin/rails spotter:tls` in `web`, then restart Spotter).
Copy `web/storage/tls/spotter-ca.pem` to that device (AirDrop or email it) and
trust it:

- **iPhone / iPad:** open it and install the profile (Settings > General > VPN
  & Device Management), then turn on full trust for "Spotter local CA" in
  Settings > General > About > Certificate Trust Settings.
- **Android:** Settings > Security > Encryption & credentials > Install a
  certificate > CA certificate (the menu names vary by phone).
- **Mac:** open it, then in Keychain Access set "Spotter local CA" to Always
  Trust.

Then open the https address the Spotter window shows (port 3443) and sign in again (https keeps
its own sign-in).

## 5. Check the rig

Sign up (a username and a 4-8 digit PIN) and press **New session**. The setup
wizard runs every time, and its camera check is this rig's acceptance test.

1. **Camera:** a preview from every camera found. Pick the one that shows the
   target (go by the picture: names and numbers are only hints), or enter the
   Pi's stream URL. Pick pistol or rifle.
2. **Camera check:** live, about once a second. Adjust until every line is
   good:

   | check | good | what to do |
   |---|---|---|
   | Focus | edge fit 0.5 px or less | Focus, or move the camera. Over 1.0 px fails. |
   | Ring fit | 0.15 mm RMS or less (usually ~0.1) | Usually focus, glare or a card that isn't flat. Over 0.25 mm fails. |
   | Card flat | 0.15 mm or less | Clamp the edges, or turn the card 180 degrees. Over 0.5 mm fails. |
   | Framing | the whole target in view | Re-aim until ring 1 doesn't run off any side. |
   | Distance | 0.25 mm per pixel or less | Move the camera closer. |
   | Lighting | OK | See "Light it". |
   | View angle | for information | Corrected automatically. |

   Next unlocks at **Ready to shoot**.
3. **Sound check:** fire a few shots and watch the level of each. **Set the
   trigger level just under your quietest shot**, using the levels in your
   rig's section. Set it low: a sound with no new hole behind it is ignored and
   costs nothing, but a shot under the level is only found by the camera,
   seconds later. Shots must also last at least 180 ms, which filters out short
   clicks. Levels change from day to day and with where the mic sits, so
   re-check after moving anything. Or choose **camera only**: no mic, each
   shot found in 2-4 s, and shots less than about 5 s apart can be missed.
4. **Start:** practice, match or final; gun and pellets are optional.

Whatever the mic does, a camera check runs once a second. A shot the mic
didn't hear is still found ("found without a sound").

Fire a few shots and compare the scores with the card. Afterwards, review the
session: record your own call on every shot (step 6).

## 6. Living with it

- **Changing cards:** press **Pause**, change the card, press **Resume**. The
  engine works out whether it's the same card or a new one. Without Pause it
  still notices a card coming off and going back on.
- **Camera bumped:** press **Re-find target** between shots.
- **A shot it missed:** if it captured the shot but couldn't score it, open
  "Shot not scored - Plot it" and tap the hole.
- **Review every shot after a session.** Tap where you see the pellet's mark
  and record your ring. Your call always wins over the system's. Over time
  your calls also train the learned scorer.
- **Card change, new light, camera moved?** Run through the camera check again
  (it runs every session anyway).

## Troubleshooting

| what you see | likely cause |
|---|---|
| Camera opens but the picture is black / nothing is found | Camera permission missing: on a Mac, grant it and restart the terminal; on Linux, join the `video` group and log in again. |
| Wrong camera | Pick by the preview picture. Camera numbers change between machines. |
| Camera drops out or stutters (Rig C) | The USB run is too long or under-powered. Use an active cable, powered at the far end if it has the option. |
| Pi stream slow or lagging (Rig D) | Weak Wi-Fi, or another viewer on ustreamer's page. Move the Pi or the router closer; close other viewers. |
| Most shots "found without a sound" | Trigger level too high for this mic. Lower it in the sound check, to just under your quietest shot (around +45 for a mic at the target). |
| Shots heard but "not scored, view moving" | The camera or card moves on impact. Stiffen the mount, or move the camera off the trap. |
| Ring fit poor only sometimes | Glare coming and going, or a changing light. Steady the light. |
| "Not flat" in the same place on every card | The holder lets one edge curl. Clamp it, or turn the cards 180 degrees. |
| Holes in the black aren't found | Front light only. Backlight the card ("Light it"). |
| The range screen on another device doesn't update or talk | Use the `.local` name, and https for its mic. Keep the range screen open: leaving it stops its mic and announcer. |
| Sound doesn't play | Browsers play only after a tap on the page; tap anywhere. |

## Appendix: installing by hand

What `install.sh` does, step by step, for anyone who prefers to see it. You
need Python 3.15 and Ruby 4.0.9. Run the app with `bin/dev` in `web/`
(the development server, with a CSS watcher) or `./start-spotter`.

### macOS (by hand)

```bash
# tools (Homebrew: https://brew.sh)
brew install git python@3.15 rbenv
rbenv init                              # then open a new terminal
rbenv install 4.0.9

git clone https://github.com/mikedao/spotter.git && cd spotter

# engine
cd engine
/opt/homebrew/bin/python3.15 -m venv .venv
./.venv/bin/python -m pip install -r requirements.txt
./.venv/bin/python selftest.py          # must pass: checks the maths, no camera needed

# web app
cd ../web
bundle install && bin/rails db:prepare
bin/dev                                 # http://localhost:3000
```

**Camera and microphone permission.** Grant **camera and microphone** access
to the terminal (or VS Code) that runs `bin/dev`, in System Settings > Privacy &
Security, then quit and reopen it completely. The engine inherits this
permission. Without it, the camera opens but delivers nothing.

### Linux (by hand)

For Debian, Ubuntu and their relatives; on other distributions, install the
same libraries with your package manager.

```bash
# system libraries: camera (OpenCV), microphone (PortAudio), building Python and Ruby
sudo apt update
sudo apt install -y git curl build-essential libgl1 libglib2.0-0 libportaudio2 \
  libssl-dev libyaml-dev libffi-dev zlib1g-dev libreadline-dev libsqlite3-dev \
  libbz2-dev liblzma-dev libncurses-dev tk-dev avahi-daemon

# Python 3.15 (pyenv)
curl -fsSL https://pyenv.run | bash     # then follow its instructions to add pyenv to your shell
pyenv install 3.15

# Ruby 4.0.9 (rbenv)
git clone https://github.com/rbenv/rbenv.git ~/.rbenv
git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
~/.rbenv/bin/rbenv init                 # then open a new terminal
rbenv install 4.0.9

git clone https://github.com/mikedao/spotter.git && cd spotter

# engine
cd engine
$(pyenv prefix $(pyenv latest 3.15))/bin/python -m venv .venv
./.venv/bin/python -m pip install -r requirements.txt
./.venv/bin/python selftest.py          # must pass: checks the maths, no camera needed

# web app
cd ../web
bundle install && bin/rails db:prepare
bin/dev                                 # http://localhost:3000
```

**Camera and microphone permission.** Your user needs to be in the `video`
and `audio` groups:

```bash
sudo usermod -aG video,audio $USER      # then log out and back in
```

Webcams show up as `/dev/video0`, `/dev/video1`, ... (many have two: the
picture and a metadata device). The wizard's previews show which one is the
camera. `avahi-daemon` makes the laptop reachable as `<hostname>.local` from a
phone or tablet (Rig B); `hostname` prints the name.
