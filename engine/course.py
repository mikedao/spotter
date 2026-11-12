"""
Courses of fire and the virtual range officer (RO) that runs them.

A course is a list of steps: the RO says something (`Say`), waits (`Pause`),
or opens a timed firing window (`Window`: "start" ... "stop"). The runner walks
the steps on its own thread, by the wall clock, and tells the engine which
window any shot's impact time fell in - so a shot can be a sighter, a match
shot, or out of time.

Practice has no course: no RO, no clock, every shot counts.

Rules (verified 2026-11-11):
  Match    ISSF 10m qualification, 2026 pistol rulebook: 60 shots in 75 minutes
           after 15 minutes of preparation and sighting time, unlimited
           sighters. Training aid: "Start match" ends sighting early (SIGUSR1),
           and the RO calls 10, 5 and 1 minutes left.
  Final    classic 24-shot final (freETarget, Paris 2024): 5 min sighting, two
           5-shot series of 250 s, then 14 single shots of 50 s; a longer
           pause every 2 shots from shot 12, where eliminations would be.
  Ranking  ISSF "Ranking Match + Medal Match" final (ISSF format document,
           Dec 2022): 6 min sighting, five 5-shot series of 250 s (places
           decided after 15, 20, 25), then single-shot medal match shots of
           50 s - 8 here, the fewest that reach 16 points.

Out of time (before START, after STOP, after the end, or one shot too many in
a window) is recorded, flagged, and scores zero, as in ISSF.

Pure Python, no dependencies: the voice helper imports it for its phrases.
"""
import threading
import time
from dataclasses import dataclass, field


@dataclass(frozen=True)
class Say:
    text: str
    wait: float = 0.0          # seconds after the words, before the next step


@dataclass(frozen=True)
class Pause:
    seconds: float
    after_skip: float | None = None   # shorter, when the shooter ended the window before it early


@dataclass(frozen=True)
class Window:
    stage: str                 # "sighting" or "match"
    label: str                 # shown on the range screen: "Sighting", "Series 2", "Shot 13"
    seconds: float
    shots: int | None = None   # competition shots allowed in it; None = unlimited
    warnings: tuple = ()       # (seconds left, what the RO says)
    skippable: bool = False    # "Start match" may end it early
    start: str = "start"
    stop: str = "stop"


END = "unload. the results are final"


def _final_singles(n_from, n_to, first_text, next_text, long_after=()):
    steps = []
    for n in range(n_from, n_to + 1):
        steps += [Say(first_text if n == n_from else next_text, 5),
                  Window("match", f"Shot {n}", 50, shots=1),
                  Pause(30 if n in long_after else 15)]
    return steps


COURSES = {
    "match": {
        "name": "Match",
        "description": "60 shots in 75 minutes, after 15 minutes of sighting",
        "shots": 60, "series": 10,
        "steps": [
            Say("preparation and sighting time", 2),
            Window("sighting", "Sighting", 15 * 60, warnings=((30, "30 seconds"),),
                   skippable=True),
            Pause(30, after_skip=10),
            Say("match firing", 2),
            Window("match", "Match", 75 * 60, shots=60,
                   warnings=((600, "10 minutes left"), (300, "5 minutes left"),
                             (60, "1 minute left"))),
            Say(END),
        ],
    },
    "final": {
        "name": "Final",
        "description": "24 shots: 2 series of 5 in 250 s, then 14 single shots in 50 s",
        "shots": 24, "series": None,
        "steps": [
            Say("5 minutes preparation and sighting time", 5),
            Window("sighting", "Sighting", 5 * 60, warnings=((30, "30 seconds"),)),
            Pause(20),
            Say("for the first competition series, load", 5),
            Window("match", "Series 1", 250, shots=5),
            Pause(20),
            Say("for the next competition series, load", 5),
            Window("match", "Series 2", 250, shots=5),
            Pause(20),
            *_final_singles(11, 24, "for the next competition shot, load",
                            "for the next competition shot, load",
                            long_after=(12, 14, 16, 18, 20, 22)),
            Say(END),
        ],
    },
    "ranking": {
        "name": "Final (ranking + medal match)",
        "description": "25 shots in 5-shot series of 250 s, then 8 medal match shots in 50 s",
        "shots": 33, "series": None,
        "steps": [
            Say("6 minutes preparation and sighting time", 5),
            Window("sighting", "Sighting", 6 * 60, warnings=((30, "30 seconds"),)),
            Pause(20),
            *[s for i in range(1, 6) for s in (
                Say("for the first ranking match series, load" if i == 1
                    else "for the next ranking match series, load", 5),
                Window("match", f"Series {i}", 250, shots=5),
                Pause(30 if i >= 3 else 20))],
            Say("medal match", 30),
            *_final_singles(26, 33, "for the first medal match shot, load",
                            "for the next medal match shot, load"),
            Say(END),
        ],
    },
}


def phrases():
    """Everything the RO can say, for the voice cache."""
    out = []
    for c in COURSES.values():
        for s in c["steps"]:
            if isinstance(s, Say):
                out.append(s.text)
            elif isinstance(s, Window):
                out += [s.start, s.stop] + [w for _, w in s.warnings]
    return list(dict.fromkeys(out))


@dataclass
class _Open:
    window: Window
    index: int                 # its position among the course's windows
    opened: float
    closed: float | None = None
    shots: int = 0             # shots counted in it


class Runner:
    """
    Runs one course on its own thread. `speak(text)` must return something
    with poll() (None while playing), like the engine's announcements;
    `phase(info)` is told every change, for the range screen.

        r = Runner(COURSES["final"], speak, phase); r.start()
        r.classify(impact_time)   # -> {"stage", "label", "series", "number", "penalty"}
        r.skip()                  # "Start match": end a skippable sighting now
        r.done                    # True once "the results are final"
    """

    def __init__(self, course, speak, phase=lambda info: None, clock=time.time):
        self.course, self.speak, self.on_phase, self.clock = course, speak, phase, clock
        self.windows = []          # _Open, in order
        self.lock = threading.Lock()
        self._skip = threading.Event()
        self.started = None
        self.finished = None
        self.match_number = 0      # competition shots so far (in or out of time)
        self._skipped = False      # the last window was ended early ("Start match")

    @property
    def done(self):
        return self.finished is not None

    def start(self):
        threading.Thread(target=self._run, daemon=True).start()

    def skip(self):
        self._skip.set()

    # -- the clock -----------------------------------------------------
    def _say(self, text):
        h = self.speak(text)
        deadline = self.clock() + 15
        while h is not None and h.poll() is None and self.clock() < deadline:
            time.sleep(0.05)

    def _sleep(self, seconds):
        end = self.clock() + seconds
        while self.clock() < end:
            time.sleep(min(0.1, max(0.0, end - self.clock())))

    def _phase(self, kind, label, ends=None, **extra):
        self.on_phase({"phase": kind, "label": label,
                       "ends_at": ends, **extra})

    def _run(self):
        self.started = self.clock()
        n = 0
        for step in self.course["steps"]:
            if isinstance(step, Say):
                self._phase("command", step.text)
                self._say(step.text)
                self._sleep(step.wait)
            elif isinstance(step, Pause):
                secs = (step.after_skip if step.after_skip is not None and self._skipped
                        else step.seconds)
                self._phase("pause", "Wait", self.clock() + secs)
                self._sleep(secs)
            else:
                self._window(step, n)
                n += 1
        self.finished = self.clock()
        self._phase("done", "Results are final")

    def _window(self, w, index):
        self._say(w.start)
        self._skip.clear()
        self._skipped = False
        opened = self.clock()
        ow = _Open(w, index, opened)
        with self.lock:
            self.windows.append(ow)
        ends = opened + w.seconds
        self._phase("window", w.label, ends, stage=w.stage, shots=w.shots,
                    skippable=w.skippable)
        warned = set()
        while True:
            now = self.clock()
            left = ends - now
            if left <= 0:
                break
            if w.skippable and self._skip.is_set():
                self._skipped = True
                break
            with self.lock:
                full = w.shots is not None and ow.shots >= w.shots
            if full:
                break
            for secs, text in w.warnings:
                if left <= secs and secs not in warned:
                    warned.add(secs)
                    self.speak(text)
            time.sleep(0.1)
        with self.lock:
            ow.closed = self.clock()
        self._say(w.stop)

    # -- shots -----------------------------------------------------------
    def classify(self, at, grace=0.0):
        """Which window a shot at wall-clock `at` belongs to. `grace` widens a
        window's close for shots found by the camera, whose time is when they
        were SEEN (2-4 s late), not when they hit."""
        with self.lock:
            ow = next((o for o in reversed(self.windows)
                       if o.opened - 0.5 <= at and (o.closed is None or at <= o.closed + grace)),
                      None)
            any_match = any(o.window.stage == "match" for o in self.windows)
            if ow is not None and ow.window.stage == "sighting":
                return {"stage": "sighter", "label": ow.window.label}
            if ow is None and not any_match:
                return {"stage": "sighter", "label": "Sighting",
                        "penalty": None}      # a sighter out of time costs nothing
            self.match_number += 1
            if ow is None:
                last = self.windows[-1]
                why = "after the end" if self.done else "out of time"
                return {"stage": "match", "label": last.window.label,
                        "series": self._series(last), "number": self.match_number,
                        "penalty": why}
            ow.shots += 1
            extra = ow.window.shots is not None and ow.shots > ow.window.shots
            return {"stage": "match", "label": ow.window.label,
                    "series": self._series(ow), "number": self.match_number,
                    "penalty": "extra shot" if extra else None}

    def _series(self, ow):
        """Series number: every 10 shots in a match, each window in a final."""
        every = self.course.get("series")
        if every:
            return (self.match_number - 1) // every + 1
        return sum(1 for o in self.windows[:self.windows.index(ow) + 1]
                   if o.window.stage == "match")
