"""
What Spotter says, broken into the short pieces a voice speaks - shared by the
engine (which announces) and voice/speak.py (which renders with Kokoro, on its
own Python). Pure Python, no dependencies, so both can import it.

An announcement such as "shot 4. 9.0, low. line call" is spoken as
pieces with real silence between them: a longer pause between sentences, a
shorter one at commas (the shooter asked for clear pauses - run-together
phrases are hard to take in while concentrating on the next shot). Each piece
is rendered once per voice and cached, so playback is instant; PIECES lists
every piece the engine can say, so the cache can be filled ahead of time.
"""

import course                                   # noqa: E402 - pure Python too

SENTENCE_GAP_S = 0.55
COMMA_GAP_S = 0.25

# Kokoro v1.0's English voices: id -> (name, accent, gender).
VOICES = {
    "af_heart": ("Heart", "American", "female"), "af_alloy": ("Alloy", "American", "female"),
    "af_aoede": ("Aoede", "American", "female"), "af_bella": ("Bella", "American", "female"),
    "af_nicole": ("Nicole", "American", "female"), "af_nova": ("Nova", "American", "female"),
    "af_sarah": ("Sarah", "American", "female"), "af_sky": ("Sky", "American", "female"),
    "am_adam": ("Adam", "American", "male"), "am_fenrir": ("Fenrir", "American", "male"),
    "am_michael": ("Michael", "American", "male"), "am_santa": ("Santa", "American", "male"),
    "bf_alice": ("Alice", "British", "female"), "bf_emma": ("Emma", "British", "female"),
    "bf_isabella": ("Isabella", "British", "female"), "bf_lily": ("Lily", "British", "female"),
    "bm_daniel": ("Daniel", "British", "male"), "bm_fable": ("Fable", "British", "male"),
    "bm_george": ("George", "British", "male"),
}
DEFAULT_VOICE = "af_heart"

# What the rig check / voice picker plays: a normal shot, a flagged one, the end
# of a card, and the ready call.
SAMPLE = ["shot 3. 8.5, shot high left",
          "shot 4. 9.0, shot a touch low. line call",
          "shot 10. 10.3, center, inner ten. that's 10. new card please",
          "ready"]

DIRECTIONS = ["center", "right", "high right", "high", "high left",
              "left", "low left", "low", "low right"]
# How a direction is said (phase1._spoken_direction): "shot low", with how far
# out - "a touch" (rings 10-9), plain (8-7), "well" (6 or worse). One piece each,
# because a direction said on its own ("low.") sounded wrong.
DEGREES = ["a touch ", "", "well "]
DIRECTION_PHRASES = ["center"] + [f"shot {g}{d}" for g in DEGREES for d in DIRECTIONS[1:]]
FLAGS = ["line call", "ring uncertain", "overlaps a hole", "rough hole",
         "found without a sound"]
FIXED = ["ready", "inner ten", "new card please", "card off", "new card",
         "same card", "not scored", "view moving", "shot not scored",
         "camera connection lost", "geometry warning", "consider a fresh card",
         "please wait", "scoring paused"]
MAX_SHOTS = 60
# A match or final (course.py): a sighter is "sighter"; a shot out of time is
# flagged "<why>, scores zero".
COURSE_SHOT = ["sighter", "out of time", "after the end", "extra shot", "scores zero"]


def lang(voice):
    return "en-gb" if voice.startswith("b") else "en-us"


def piece(text):
    """The normal form of one piece: what the cache is keyed on."""
    return " ".join(text.strip().strip(".,").lower().split())


def split(text):
    """An announcement -> sentences -> pieces."""
    out = []
    for sentence in text.split(". "):
        parts = [piece(p) for p in sentence.split(",")]
        parts = [p for p in parts if p]
        if parts:
            out.append(parts)
    return out


def pieces():
    """Every piece the engine can say, most frequent first (fill order)."""
    out = ["ready"]
    out += [f"shot {n}" for n in range(1, 11)]
    out += [f"{r / 10:.1f}" for r in range(109, -1, -1)]      # 10.9 .. 0.0
    out += DIRECTION_PHRASES + FLAGS + FIXED + COURSE_SHOT
    out += [p for text in course.phrases() for sentence in split(text) for p in sentence]
    out += [f"that's {n}" for n in range(1, MAX_SHOTS + 1)]    # end of card
    out += [f"shot {n}" for n in range(11, MAX_SHOTS + 1)]
    seen, ordered = set(), []
    for p in map(piece, out):
        if p not in seen:
            seen.add(p)
            ordered.append(p)
    return ordered
