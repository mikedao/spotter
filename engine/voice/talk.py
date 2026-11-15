"""
The personality announcer's brain: a small language model fine-tuned to say
things the way one personality would (personalities/<name>.py).

  talk.py data   --personality katey     training examples -> cache/talk/<name>/data/
  talk.py sample --personality katey     a few examples, to read
  talk.py train  --personality katey     fine-tune (~1.5 h on the Studio) -> cache/talk/<name>/adapter
  talk.py test   --personality katey     the held-out examples: speed, checks, how many sentences are new
  talk.py serve  --personality katey     live, for the web app (127.0.0.1; see serve())

The examples are built from the personality's building blocks and REAL facts:
the model sees what the web app will send (the facts of the moment, numbers
as words) and learns to answer in character. Every number in an answer comes
from the facts, so the model never learns to make one up.
"""

import argparse
import importlib
import json
import random
import re
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
CACHE = HERE / "cache" / "talk"
DIRECTIONS = ["right", "high right", "high", "high left", "left", "low left", "low", "low right"]

ONES = "zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen " \
       "seventeen eighteen nineteen".split()
TENS = "_ _ twenty thirty forty fifty sixty seventy eighty ninety".split()


def words(n):
    """A whole number as words: 94 -> ninety four, 541 -> five hundred forty one."""
    n = int(n)
    if n < 20:
        return ONES[n]
    if n < 100:
        return TENS[n // 10] + ("" if n % 10 == 0 else " " + ONES[n % 10])
    rest = n % 100
    return ONES[n // 100] + " hundred" + ("" if rest == 0 else " " + words(rest))


# How a shot's SCORE is given and said (2026-11-14, the shooter): the RING below
# 10 ("nine"), the decimal from 10 up ("ten four") - as the standard announcer.
# Written into the trained model (adapter/format.json) by `train`; `serve` turns
# the web app's facts (always with the decimal) into this form for such a model.
SCORE_FORMAT = "ring"


def score_words(d, rng=None):
    """A shot's score as given / said: the ring below 10, else decimal_words."""
    return words(int(d)) if d < 10.0 else decimal_words(d, rng)


def decimal_words(d, rng=None):
    """9.6 -> nine six (or nine point six); 10.0 -> ten oh / ten flat."""
    whole, tenth = divmod(round(d * 10), 10)
    if rng is None:
        return f"{words(whole)} {ONES[tenth] if tenth else 'oh'}"
    if tenth == 0:
        return rng.choice([f"{words(whole)} oh", f"{words(whole)} flat", f"{words(whole)} point oh"])
    return rng.choice([f"{words(whole)} {ONES[tenth]}", f"{words(whole)} point {ONES[tenth]}"])


MAX_WORDS, MAX_WORDS_CARD = 18, 30


class Builder:
    def __init__(self, p, rng):
        self.p, self.rng = p, rng

    def fill(self, text, **values):
        values.setdefault("pet", self.rng.choice(self.p.PETS))
        values.setdefault("name", self.p.NAME)
        for k, v in values.items():
            text = text.replace("{" + k + "}", str(v))
        return text

    def pick(self, options, **values):
        return self.fill(self.rng.choice(options), **values)

    def step(self, decimal):
        return next(s for s in self.p.STEPS if round(decimal, 1) >= s[0])

    # ---- the facts, as the web app will send them --------------------------------
    @staticmethod
    def facts(event, **kv):
        lines = [f"event: {event}"] + [f"{k}: {v}" for k, v in kv.items() if v not in (None, "", [])]
        return "\n".join(lines)

    # ---- a shot -----------------------------------------------------------------
    def shot(self):
        r = self.rng
        p = self.p
        band = r.choices(["inner", "ten", "good9", "ok9", "eight", "seven", "six", "awful"],
                         [10, 14, 20, 16, 18, 10, 6, 6])[0]
        decimal = {"inner": r.uniform(10.3, 10.9), "ten": r.uniform(10.0, 10.5), "good9": r.uniform(9.5, 9.95),
                   "ok9": r.uniform(9.0, 9.45), "eight": r.uniform(8.0, 8.95), "seven": r.uniform(7.0, 7.95),
                   "six": r.uniform(6.0, 6.95), "awful": r.uniform(0.0, 5.95)}[band]
        decimal = int(decimal * 10) / 10.0
        inner = band == "inner"
        direction = "center" if inner else r.choice(DIRECTIONS)
        frm, step, step_text = self.step(decimal)
        card_end = r.random() < 0.12                       # a card / series ends on a tenth shot
        n = r.choice(range(10, 61, 10)) if card_end else r.choice([k for k in range(1, 61) if k % 10])
        spoken = score_words(decimal)
        facts = {"shot": words(n), "score": spoken, "how far": "inner ten" if inner else step_text,
                 "direction": direction}

        # more facts to riff on (each only sometimes, as a real session would have them)
        extra = []                                      # what she may say about them
        ring = int(decimal)
        want_prev = r.random() < 0.5
        if card_end:
            pass
        elif n % 10 == 1 and r.random() < 0.6:
            facts["card shot"] = "first"
            extra.append(self.pick(p.CARD_FIRST))
        elif n % 10 == 9 and r.random() < 0.6:
            facts["card shot"] = "nine of ten"
            extra.append(self.pick(p.CARD_NINTH))
        elif n % 10 >= 3 and r.random() < 0.3:
            avg = decimal_words(r.uniform(8.0, 9.9))
            facts["card average"] = avg
            extra.append(self.pick(p.CARD_AVERAGE, avg=avg))
        if r.random() < 0.3:
            when = r.choice(list(p.TIME))
            facts["time"] = when
            extra.append(self.pick(p.TIME[when]))
        if r.random() < 0.15:
            mins = r.choice([40, 50, 60, 70, 80, 90, 100, 120])
            span = (f"{words(mins)} minutes" if mins < 60 else "an hour" if mins == 60 else
                    "two hours" if mins == 120 else f"an hour {words(mins - 60)}")
            facts["shooting for"] = span
            extra.append(self.pick(p.LONG_SESSION, **{"for": span}))
        if ring >= 10 and r.random() < 0.3:
            t = r.randint(2, 25)
            facts["tens today"] = words(t)
            extra.append(self.pick(p.TENS_TODAY, tens=words(t)))

        say_score = score_words(decimal, r)
        deg = r.choice(p.CENTER) if inner else self.fill(r.choice(p.DEGREE[step]), dir=direction)
        out = []
        optional = []                                   # parts dropped first when a line runs long
        sighter = penalty = None
        if r.random() < 0.06:
            sighter = True
            facts["sighter"] = "yes"
            out.append(self.pick(p.SIGHTER))
        elif r.random() < 0.04:
            penalty = r.choice(list(p.PENALTY))
            facts["penalty"] = f"{penalty}, scores zero"
        quality = {"inner": "inner", "ten": "ten", "good9": "good9", "ok9": "ok9", "eight": "eight",
                   "seven": "seven", "six": "awful", "awful": "awful"}[band]
        woven = not sighter and not penalty and r.random() < 0.35
        if woven:
            out.append(self.pick(p.WOVEN[quality], score=say_score, deg=deg))
        else:
            out.append(self.pick(p.SCORE_LINES, score=say_score, deg=deg, n=words(n)))
        if penalty:
            out.append(self.pick(p.PENALTY[penalty]))

        # at most one moment, as the web app's Commentary picks them
        moment = None
        if not sighter and not penalty:
            roll = r.random()
            if band in ("inner", "ten") and roll < 0.25:
                k = r.randint(3, 8)
                facts["moment"] = f"{words(k)} tens in a row"
                moment = self.pick(p.STREAK_TENS, n=words(k))
            elif band in ("inner", "ten", "good9", "ok9") and roll < 0.35:
                k = r.choice([5, 10])
                facts["moment"] = f"{words(k)} in a row in the nine or better"
                moment = self.pick(p.NINE_RUN, n=words(k))
            elif band in ("eight", "seven", "six", "awful") and roll < 0.2:
                k = r.randint(5, 12)
                facts["moment"] = f"after {words(k)} in a row in the nine or better"
                moment = self.pick(p.DROP_AFTER_RUN, n=words(k))
            elif band in ("good9", "ok9", "eight", "seven") and direction != "center" and roll < 0.4:
                facts["moment"] = f"third in a row {direction}"
                moment = self.pick(p.PATTERN, dir=direction)
                if r.random() < 0.8:
                    facts["tip"] = "yes"
                    moment += " " + self.pick(p.TIPS[direction])
            elif band in ("eight", "seven", "six", "awful") and roll < 0.5:
                facts["moment"] = "a flyer, well away from the group"
                moment = self.pick(p.FLYER)
        if want_prev:                                   # the shot before, consistent with the moment
            m = facts.get("moment", "")
            if "tens in a row" in m:
                prev = r.uniform(10.0, 10.9)
            elif "nine or better" in m:
                prev = r.uniform(9.0, 10.9)
            else:
                prev = min(10.9, max(0.0, decimal + r.uniform(-2.5, 2.5)))
            prev = int(prev * 10) / 10.0
            facts["previous"] = score_words(prev)
            pool = p.PREV_BETTER if ring > int(prev) else p.PREV_WORSE if ring < int(prev) else p.PREV_SAME
            extra.insert(0, self.pick(pool))
        def opt(part):
            optional.append(part)
            out.append(part)

        if moment:
            if r.random() < 0.4 and not card_end:
                opt(self.pick(p.REACT[quality]))
            out.append(moment)
        elif not sighter and not penalty and not woven and not card_end:
            opt(self.pick(p.REACT[quality]))
            if r.random() < 0.05:                       # very chatty: now and then two
                opt(self.pick(p.REACT[quality]))
            if quality in ("inner", "ten") and r.random() < 0.08:
                opt(self.fill(r.choice(["{name} approves.", "that's {name} certified.", "{name} likes that."])))

        if extra and not sighter and not card_end and r.random() < 0.3:
            opt(r.choice(extra))

        if r.random() < 0.1:
            flag = r.choice(list(p.FLAGS))
            facts["flag"] = flag
            out.append(self.pick(p.FLAGS[flag]))

        # every tenth shot: the card (or series) and how it compares
        if card_end and not sighter:
            good = band in ("inner", "ten", "good9", "ok9")
            total = r.randint(86, 100) if good else r.randint(70, 92)
            series = r.random() < 0.3
            facts["card" if not series else "series"] = f"done, total {words(total)}"
            out.append(self.pick(p.SERIES_DONE if series else p.CARD_DONE, total=words(total)))
            kind = r.choice(["best_today", "personal_best", "better", "worse", "worse", "better", "first", "same"])
            d = r.randint(1, 9)
            facts["compared"] = {"best_today": "best today", "personal_best": "personal best",
                                 "better": f"{words(d)} better than the last", "worse": f"{words(d)} worse than the last",
                                 "first": "first today", "same": "same as the last"}[kind]
            out.append(self.pick(p.COMPARE[kind], d=words(d)))
            if not series and r.random() < 0.7:
                facts["new card"] = "yes"
                out.append(self.pick(p.NEW_CARD_PLEASE))
            if series and r.random() < 0.3:
                if r.random() < 0.5:
                    t = r.randint(250, 300)
                    facts["halfway"] = f"thirty shots, total {words(t)}"
                    out.append(self.pick(p.HALFWAY, total=words(t)))
                else:
                    facts["last series"] = "yes"
                    out.append(self.pick(p.LAST_SERIES))
        # SHORT (2026-11-14: in the demo, shots 10 s apart came faster than she
        # finished): an ordinary shot <= MAX_WORDS, a card's last <= MAX_WORDS_CARD;
        # optional parts go first, never the score, a moment, a flag or the card.
        cap = MAX_WORDS_CARD if card_end else MAX_WORDS
        while len(" ".join(out).split()) > cap and optional:
            out.remove(optional.pop())
        return self.facts("shot", **facts), " ".join(out)

    # ---- the ends, and the engine's own lines --------------------------------------
    def match_done(self):
        r, p = self.rng, self.p
        total, best = r.randint(480, 590), r.randint(85, 100)
        out = [self.pick(p.MATCH_DONE, total=words(total)), self.pick(p.BEST_SERIES, best=words(best)),
               self.pick(p.MATCH_SIGNOFF)]
        return self.facts("match over", **{"final score": words(total), "best series": words(best)}), " ".join(out)

    def session_done(self):
        r, p = self.rng, self.p
        shots = r.randint(10, 90)
        avg = decimal_words(r.uniform(7.5, 9.9))
        facts = {"shots": words(shots), "average": avg}
        out = [self.pick(p.SESSION_DONE), self.pick(p.SESSION_FACTS, shots=words(shots), avg=avg)]
        if shots >= 20 and r.random() < 0.7:
            best = r.randint(80, 100)
            facts["best card"] = words(best)
            out.append(self.pick(p.SESSION_BEST, best=words(best)))
        out.append(self.pick(p.SESSION_SIGNOFF))
        return self.facts("session over", **facts), " ".join(out)

    def engine(self):
        what = self.rng.choice(list(self.p.ENGINE))
        return self.facts(what), self.pick(self.p.ENGINE[what])

    def example(self):
        kind = self.rng.choices(["shot", "engine", "session", "match"], [80, 12, 5, 3])[0]
        user, answer = {"shot": self.shot, "engine": self.engine, "session": self.session_done,
                        "match": self.match_done}[kind]()
        system = self.p.PERSONA.replace("{name}", self.p.NAME)
        return {"messages": [{"role": "system", "content": system}, {"role": "user", "content": user},
                             {"role": "assistant", "content": answer}]}


NUMBER_WORDS = set(ONES) | set(TENS[2:]) | {"hundred"}
FORBIDDEN = re.compile(r"\b(goal|pace|qualif\w*|trials?|olympics?|five hundred sixty five|565)\b")
# never anything near suicide or self-harm, not even as a joke (the shooter, 2026-11-14)
SELF_HARM = re.compile(r"\b(suicid\w*|kill (my|your|him|her)sel(f|ves)|delete (my|your)sel(f|ves)|end (it all|my life|your life)|self[- ]harm\w*|slit\w*|hang (my|your)self|overdos\w*|unalive\w*|kms|kys|jump off)\b")


_VOCAB = None


def vocab():
    """Words she may use: English (the system dictionary) and every word in her training answers."""
    global _VOCAB
    if _VOCAB is None:
        words_file = Path("/usr/share/dict/words")
        _VOCAB = {w.lower() for w in words_file.read_text().split()} if words_file.exists() else set()
        for name in (CACHE.iterdir() if CACHE.exists() else []):
            train = name / "data" / "train.jsonl"
            if train.exists():
                for line in train.read_text().splitlines():
                    _VOCAB |= set(re.findall(r"[a-z']+", json.loads(line)["messages"][2]["content"]))
    return _VOCAB


SUFFIXES = ("'s", "ing", "ed", "es", "s", "ly", "er", "est", "d", "y", "n't")


def is_word(w):
    """A real word: in the vocabulary, or a known word plus a common ending (drowned, tears)."""
    known = vocab()
    w = w.strip("'-")
    if not known or w in known:
        return True
    if "-" in w:
        return all(is_word(part) for part in w.split("-") if part)
    for suf in SUFFIXES:
        if w.endswith(suf) and len(w) - len(suf) >= 2:
            stem = w[: -len(suf)]
            if stem in known or stem + "e" in known or (len(stem) > 2 and stem[-1] == stem[-2] and stem[:-1] in known) \
                    or (suf in ("ed", "es", "er", "est", "ly") and stem.endswith("i") and stem[:-1] + "y" in known):
                return True
    return False


def check(facts_text, answer):
    """Why this answer must not be spoken ([] = fine): the same rules the web app
    applies before a line is said. facts_text is what the model was given."""
    facts = dict(line.split(": ", 1) for line in facts_text.splitlines() if ": " in line)
    why = []
    if re.search(r"[^a-z0-9 .,'\-]", answer):
        why.append("characters")
    if not answer.strip() or len(answer.split()) > 70:
        why.append("length")
    # never the goal - but a real score that happens to be 565 is a fact, not the goal
    spoken = answer
    for value in (v for line in facts_text.splitlines() for k, _, v in [line.partition(": ")] if k != "event"):
        spoken = spoken.replace(value, "")
    if FORBIDDEN.search(spoken):
        why.append("goal")
    if SELF_HARM.search(answer):
        why.append("self-harm")
    if not all(is_word(w) for w in re.findall(r"[a-z][a-z'-]*", answer)):
        why.append("not a word")
    if facts.get("event") == "shot":
        score = facts["score"].split()
        if len(score) == 1:                        # the ring (below 10): said alone
            ring = score[0]
            forms = [ring]
            tenths = "|".join(ONES[:10] + ["oh", "flat"])
            given = [v for k, v in facts.items() if k != "score"]          # "card average: eight two" is a fact
            if any(not any(m.group(0) in v or m.group(0).replace(" point", "") in v for v in given)
                   for m in re.finditer(rf"\b{ring}\s+(point\s+)?({tenths})\b", answer)):
                why.append("decimal")
        else:
            whole, tenth = score[0], score[-1]
            forms = [f"{whole} {tenth}", f"{whole} point {tenth}"]
            if tenth == "oh":
                forms += [f"{whole} flat", f"{whole} point oh", f"{whole} zero"]
        if not any(re.search(rf"\b{f}\b", answer) for f in forms):
            why.append("score")
        d = facts["direction"]
        if d == "center":
            ok = re.search(r"\b(center|middle)\b", answer)
        elif " " in d:
            ok = re.search(rf"\b{d}\b", answer)
        elif d in ("high", "low"):                 # "low", not "low left"
            ok = re.search(rf"\b{d}\b(?!\s+(left|right))", answer)
        else:                                      # "left", not "low left"
            ok = re.search(rf"(?<!high )(?<!low )\b{d}\b", answer)
        if not ok:
            why.append("direction")
    given = set(re.findall(r"[a-z]+", facts_text)) | {"one", "ten", "three"}
    # a ring named as a JOKE, not a score: "technically a nine, emotionally a seven"
    jokes = re.sub(r"\b(emotionally a|the energy of a|the vibe of a)\s+[a-z]+", "", answer)
    made_up = {w for w in re.findall(r"[a-z]+", jokes) if w in NUMBER_WORDS and w not in given}
    if made_up or re.search(r"\d", answer):
        why.append("numbers")
    return why


def personality(name):
    return importlib.import_module(f"personalities.{name}")


def load(name, adapter="adapter"):
    """The base model with this personality's fine-tune (a folder in cache/talk/<name>)."""
    from mlx_lm import load as mlx_load
    base = json.loads((CACHE / name / adapter / "adapter_config.json").read_text())["model"]
    return mlx_load(base, adapter_path=str(CACHE / name / adapter))


def say(model, tok, system, facts, temp=0.8, min_p=0.0):
    from mlx_lm import generate
    from mlx_lm.sample_utils import make_sampler
    prompt = tok.apply_chat_template([{"role": "system", "content": system}, {"role": "user", "content": facts}],
                                     add_generation_prompt=True, tokenize=False)
    return generate(model, tok, prompt=prompt, max_tokens=90, sampler=make_sampler(temp=temp, min_p=min_p)).strip()


def sentences(text):
    return [x.strip(" ,") for x in re.split(r"[.]", text) if x.strip(" ,")]


def test(name, temp=0.8, tries=1, show=25, min_p=0.0):
    """The held-out examples: how fast, how many pass the checks, how many of her
    sentences are NEW (not in the training answers). tries: write again when a
    line fails the checks (the app has ~2.5 s), the speed is for all tries."""
    model, tok = load(name)
    rows = [json.loads(line) for line in (CACHE / name / "data" / "test.jsonl").read_text().splitlines()]
    known = {x for line in (CACHE / name / "data" / "train.jsonl").read_text().splitlines()
             for x in sentences(json.loads(line)["messages"][2]["content"])}
    say(model, tok, rows[0]["messages"][0]["content"], "event: ready")           # warm up
    times, first_fail, all_fail, new, total, shown = [], 0, 0, 0, 0, 0
    for row in rows:
        system, facts = row["messages"][0]["content"], row["messages"][1]["content"]
        t = time.time()
        for attempt in range(tries):
            answer = say(model, tok, system, facts, temp=temp, min_p=min_p)
            why = check(facts, answer)
            if attempt == 0 and why:
                first_fail += 1
            if not why:
                break
        times.append(time.time() - t)
        all_fail += bool(why)
        fresh = [x for x in sentences(answer) if x not in known]
        new += len(fresh)
        total += len(sentences(answer))
        if shown < show and fresh:
            shown += 1
            print(f"  {answer}  [{attempt + 1} tries, {times[-1]:.2f} s]{'  FAILS: ' + ', '.join(why) if why else ''}")
    times.sort()
    print(f"temp {temp}, min_p {min_p}, {tries} tries: new sentences {new}/{total} ({100 * new / total:.0f}%), "
          f"first try failed {first_fail}/{len(rows)}, all tries failed {all_fail}/{len(rows)}; "
          f"median {times[len(times)//2]:.2f} s, 90% {times[int(len(times)*.9)]:.2f} s, max {times[-1]:.2f} s")


# Live: how much risk she takes (2026-11-14, measured on held-out facts: at 1.3
# with min-p 0.1 no line failed the checks after 3 tries; without min-p a high
# temperature mostly wrote junk words) and how long the web app waits for her.
LIVE_TEMP, LIVE_MIN_P, LIVE_TRIES, LIVE_BUDGET_S = 1.3, 0.1, 3, 2.5
PIECE = re.compile(r"^[a-z0-9][a-z0-9 .,'-]{0,79}$")      # a voice piece, as the web app's Voice::PIECE


def speak_line(model, tok, system, facts, budget_s=LIVE_BUDGET_S):
    """Her line for these facts, checked: (answer, pieces, why, tries). why = []
    when it may be said; written again (up to LIVE_TRIES, within budget_s) when not."""
    import voicelines
    t0 = time.time()
    for attempt in range(1, LIVE_TRIES + 1):
        answer = say(model, tok, system, facts, temp=LIVE_TEMP, min_p=LIVE_MIN_P)
        pieces = voicelines.split(answer)
        why = check(facts, answer)
        if not pieces or any(not PIECE.match(p) for sentence in pieces for p in sentence):
            why.append("pieces")
        if not why or time.time() - t0 > budget_s:
            return answer, pieces, why, attempt
    return answer, pieces, why, attempt


def model_format(name, adapter="adapter"):
    """The score format a trained model expects: "ring" (adapter/format.json,
    written by train) or "decimal" (models trained before 2026-11-14)."""
    path = CACHE / name / adapter / "format.json"
    return json.loads(path.read_text()).get("score", "decimal") if path.exists() else "decimal"


def to_format(facts, fmt):
    """The web app's facts (scores always with the decimal: "score: nine six") in
    the model's form: for a "ring" model a score below 10 is its ring ("nine")."""
    if fmt != "ring":
        return facts
    lines = []
    for line in facts.splitlines():
        key, _, value = line.partition(": ")
        parts = value.split()
        if key in ("score", "previous") and len(parts) == 2 and parts[0] in ONES[:10]:
            line = f"{key}: {parts[0]}"
        lines.append(line)
    return "\n".join(lines)


def likely_pieces(name):
    """Every piece she is likely to say, most used first: the pieces of her
    training answers (she mostly reuses them; the 2,000 most used are 98% of
    what she says) and every score as she says it."""
    import collections
    import voicelines
    counts = collections.Counter()
    for split in ("train", "valid"):
        path = CACHE / name / "data" / f"{split}.jsonl"
        if path.exists():
            for line in path.read_text().splitlines():
                for sentence in voicelines.split(json.loads(line)["messages"][2]["content"]):
                    counts.update(sentence)
    out = [piece for piece, _ in counts.most_common()]
    out += [words(n) for n in range(10)]
    for d in range(110):
        whole, tenth = divmod(d, 10)
        forms = ([f"{words(whole)} oh", f"{words(whole)} flat", f"{words(whole)} point oh"] if tenth == 0 else
                 [f"{words(whole)} {ONES[tenth]}", f"{words(whole)} point {ONES[tenth]}"])
        out += forms
    return list(dict.fromkeys(out))


def serve(name, port, adapter="adapter"):
    """The personality, live, for the web app: 127.0.0.1:PORT.
      GET  /health                      {"ready": true, "personality", "voice", "prepared", "of"}
      POST /say {"facts": "event: ..."} {"ok", "text", "sentences" [[pieces]], "tries", "seconds"}
    A line that passes the checks comes back with every piece already rendered in
    the personality's voice (the web app's voice cache), so the range screen plays
    it at once; ok false (with why) and the web app says the standard line."""
    import socketserver
    import threading
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
    import speak

    p = personality(name)
    model, tok = load(name, adapter)
    voice = speak.Voice(p.VOICE)
    system = p.PERSONA.replace("{name}", p.NAME)
    fmt = model_format(name, adapter)                           # "ring" / "decimal" scores
    say(model, tok, system, "event: ready")                    # warm up
    lock = threading.Lock()                                     # one line at a time (one GPU)

    # Her likely pieces, rendered while idle so a line is ready at once: its own
    # Kokoro on 2 cores, so it never slows a live engine (2026-11-12: renders on
    # every core pushed the load to ~170).
    todo = likely_pieces(name)
    progress = {"prepared": 0, "of": len(todo)}

    def prewarm():
        background = speak.Voice(p.VOICE, threads=2)
        for piece in todo:
            if not background.exported(piece).exists() and not background._piece_path(piece).exists():
                try:
                    background.piece(piece)
                except Exception as e:                            # one bad piece never stops the rest
                    print(json.dumps({"prewarm_error": piece, "error": str(e)}), flush=True)
            progress["prepared"] += 1

    threading.Thread(target=prewarm, daemon=True).start()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def reply(self, code, body):
            data = json.dumps(body).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            if self.path == "/health":
                return self.reply(200, {"ready": True, "personality": name, "voice": p.VOICE, **progress})
            self.reply(404, {"error": "not found"})

        def do_POST(self):
            if self.path != "/say":
                return self.reply(404, {"error": "not found"})
            try:
                req = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
                facts = to_format(str(req["facts"]), fmt)
                t0 = time.time()
                with lock:
                    answer, pieces, why, tries = speak_line(model, tok, system, facts,
                                                            float(req.get("budget_s", LIVE_BUDGET_S)))
                    if not why:
                        for piece in {x for sentence in pieces for x in sentence}:
                            if not voice.exported(piece).exists():
                                voice.piece(piece)
                took = round(time.time() - t0, 2)
                print(json.dumps({"facts": facts.replace("\n", " | "), "said": answer, "ok": not why,
                                  "why": why, "tries": tries, "seconds": took}), flush=True)
                self.reply(200, {"ok": not why, "why": why, "text": answer, "sentences": pieces,
                                 "tries": tries, "seconds": took})
            except Exception as e:                                # never die on one bad request
                self.reply(500, {"ok": False, "error": f"{type(e).__name__}: {e}"})

    class Server(ThreadingHTTPServer):
        daemon_threads = True

        def server_bind(self):                                    # no FQDN lookup (it hung on macOS)
            socketserver.TCPServer.server_bind(self)
            self.server_name, self.server_port = "127.0.0.1", self.server_address[1]

    server = Server(("127.0.0.1", port), Handler)
    print(json.dumps({"ready": True, "port": server.server_address[1], "personality": name}), flush=True)
    server.serve_forever()


BASE = "mlx-community/Llama-3.2-3B-Instruct-4bit"


def train(name, iters=1000):
    """Fine-tune the base model on this personality's data (LoRA; ~1 h on the
    Studio, the GPU flat out - NOT during a session). The old fine-tune is kept
    as adapter-prev."""
    import shutil
    import subprocess
    import sys
    here = CACHE / name
    if (here / "adapter").exists():
        shutil.rmtree(here / "adapter-prev", ignore_errors=True)
        (here / "adapter").rename(here / "adapter-prev")
    cmd = [sys.executable, "-u", "-m", "mlx_lm", "lora", "--model", BASE, "--train", "--data", str(here / "data"),
           "--adapter-path", str(here / "adapter"), "--fine-tune-type", "lora", "--mask-prompt", "--num-layers", "16",
           "--batch-size", "8", "--iters", str(iters), "--learning-rate", "1e-4", "--steps-per-report", "50",
           "--steps-per-eval", "200", "--val-batches", "25", "--max-seq-length", "512", "--save-every", "250"]
    with open(here / "train.log", "w") as log:
        subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, check=True, env={**__import__("os").environ, "PYTHONUNBUFFERED": "1"})
    # what the model was trained to expect (serve translates the facts to it)
    (here / "adapter" / "format.json").write_text(json.dumps({"score": SCORE_FORMAT}))


def main():
    ap = argparse.ArgumentParser(description="The personality announcer's brain")
    ap.add_argument("command", choices=["data", "sample", "test", "train", "serve"])
    ap.add_argument("--personality", default="katey")
    ap.add_argument("--count", type=int, default=4000)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--port", type=int, default=0, help="serve: port on 127.0.0.1 (0: any free one)")
    ap.add_argument("--adapter", default="adapter", help="serve: which fine-tune")
    ap.add_argument("--iters", type=int, default=1000, help="train: steps")
    ap.add_argument("--temp", type=float, default=1.3, help="test: how much risk she takes")
    ap.add_argument("--min-p", type=float, default=0.1, help="test: never pick a word below this share of the likeliest")
    ap.add_argument("--tries", type=int, default=3, help="test: write again when a line fails the checks")
    ap.add_argument("--show", type=int, default=0, help="test: print this many lines with something new")
    a = ap.parse_args()
    b = Builder(personality(a.personality), random.Random(a.seed))
    if a.command == "serve":
        return serve(a.personality, a.port, a.adapter)
    if a.command == "train":
        return train(a.personality, iters=a.iters)
    if a.command == "test":
        return test(a.personality, temp=a.temp, tries=a.tries, show=a.show, min_p=a.min_p)
    if a.command == "sample":
        for _ in range(a.count if a.count < 100 else 12):
            ex = b.example()["messages"]
            print(ex[1]["content"].replace("\n", " | "))
            print("  ->", ex[2]["content"], "\n")
        return
    out = CACHE / a.personality / "data"
    out.mkdir(parents=True, exist_ok=True)
    rows = [b.example() for _ in range(a.count)]
    n_valid = n_test = max(50, a.count // 20)
    splits = {"valid": rows[:n_valid], "test": rows[n_valid:n_valid + n_test], "train": rows[n_valid + n_test:]}
    for split, items in splits.items():
        (out / f"{split}.jsonl").write_text("".join(json.dumps(x) + "\n" for x in items))
    print(f"{a.count} examples -> {out} ({', '.join(f'{k} {len(v)}' for k, v in splits.items())})")


if __name__ == "__main__":
    main()
