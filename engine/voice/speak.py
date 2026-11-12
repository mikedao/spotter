#!/usr/bin/env python3
"""
Spotter's announcer voice: Kokoro text-to-speech, on its own Python (3.13 -
Kokoro's dependencies have no builds for the engine's Python yet), so the
engine talks to it as a separate process. Set up with ./setup.sh.

    .venv/bin/python speak.py serve --voice af_heart      # for the engine (below)
    .venv/bin/python speak.py prewarm --voice af_heart    # fill the cache ahead of time
    .venv/bin/python speak.py export --all                # every known piece, every voice -> web/public/voice-pieces (git)
    .venv/bin/python speak.py sample --voice bm_george    # the picker's sample, path printed
    .venv/bin/python speak.py samples                     # every voice's sample (~10 min), + web/public/voice-samples/*.m4a (in git)
    .venv/bin/python speak.py say --voice af_heart "shot 3. 8.5, high left"
    .venv/bin/python speak.py piece --voice af_heart "shot 4"   # render one piece, path printed

Every announcement is spoken as pieces with real silence between them
(voicelines.split: longer between sentences, shorter at commas). Each piece is
rendered once per voice and cached as a WAV (cache/<voice>/pieces/), so after
the first time an announcement is only stitched together: instant. Rendering a
new piece takes ~1.3 s, so `serve` fills the cache in the background with every
piece the engine can say (voicelines.pieces), most frequent first.

serve protocol: one JSON object per line on stdin, {"id": N, "text": "..."}; one
per line back on stdout, {"id": N, "wav": PATH} or {"id": N, "error": "..."}
(after a first {"ready": VOICE}). stdout carries nothing else.
"""
import argparse
import hashlib
import json
import os
import sys
import threading
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))          # the engine dir, for voicelines
import voicelines                              # noqa: E402

MODELS = HERE / "models"
# The web app passes both (its storage/voices and public/voice-samples); alone,
# from a terminal, the cache stays here.
CACHE = Path(os.environ.get("SPOTTER_VOICE_CACHE", HERE / "cache"))
SAMPLES = Path(os.environ.get("SPOTTER_VOICE_SAMPLES", HERE.parent.parent / "web" / "public" / "voice-samples"))
# Every piece the engine can say, for every voice, kept IN GIT as 32 kbps AAC
# (`speak.py export`): the range screen plays these straight away; only pieces
# outside this set (future personality lines) are rendered on first use.
EXPORTED = Path(os.environ.get("SPOTTER_VOICE_PIECES", HERE.parent.parent / "web" / "public" / "voice-pieces"))


def slug(p):
    """A piece's file name, the same in the cache, the export and the web app."""
    return "".join(c if c.isalnum() else "_" for c in p)


def aac(wav, out):
    """WAV -> 32 kbps AAC (.m4a) with macOS's afconvert (the bitrate the shooter
    chose by ear: ~9 KB a piece)."""
    import subprocess
    tmp = out.with_name(out.stem + ".partial.m4a")
    subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "32000", str(wav), str(tmp)], check=True)
    os.replace(tmp, out)
SPEED = 1.1
ANNOUNCEMENT_GAP_S = 1.2                       # between announcements in a sample


def log(*args):
    print(*args, file=sys.stderr, flush=True)


class Voice:
    def __init__(self, voice):
        if voice not in voicelines.VOICES:
            raise SystemExit(f"unknown voice {voice!r}; one of {', '.join(voicelines.VOICES)}")
        import numpy as np
        import soundfile as sf
        from kokoro_onnx import Kokoro
        self.np, self.sf = np, sf
        self.voice = voice
        self.kokoro = Kokoro(str(MODELS / "kokoro-v1.0.onnx"), str(MODELS / "voices-v1.0.bin"))
        self.rate = 24000
        self.dir = CACHE / voice
        (self.dir / "pieces").mkdir(parents=True, exist_ok=True)
        (self.dir / "said").mkdir(parents=True, exist_ok=True)
        self.lock = threading.Lock()

    def _piece_path(self, p):
        return self.dir / "pieces" / f"{slug(p)}.wav"

    def _write(self, path, audio):
        tmp = path.with_name(path.stem + f".{os.getpid()}.partial.wav")
        self.sf.write(tmp, audio, self.rate)
        os.replace(tmp, path)                  # never a half-written file in the cache

    def piece(self, p):
        """One piece's audio, rendered and cached on first use."""
        path = self._piece_path(p)
        if not path.exists():
            with self.lock:
                if not path.exists():
                    audio, rate = self.kokoro.create(p + ".", voice=self.voice, speed=SPEED,
                                                     lang=voicelines.lang(self.voice))
                    self.rate = rate
                    self._write(path, self._trim(audio))
        audio, self.rate = self.sf.read(path, dtype="float32")
        return audio

    def _trim(self, audio, floor=0.002, keep_s=0.03):
        loud = self.np.flatnonzero(self.np.abs(audio) > floor)
        if loud.size == 0:
            return audio
        keep = int(keep_s * self.rate)
        return audio[max(0, loud[0] - keep): loud[-1] + keep]

    def silence(self, seconds):
        return self.np.zeros(int(seconds * self.rate), self.np.float32)

    def announcement(self, text):
        chunks = []
        for i, sentence in enumerate(voicelines.split(text)):
            if i:
                chunks.append(self.silence(voicelines.SENTENCE_GAP_S))
            for j, p in enumerate(sentence):
                if j:
                    chunks.append(self.silence(voicelines.COMMA_GAP_S))
                chunks.append(self.piece(p))
        return self.np.concatenate(chunks) if chunks else self.silence(0.1)

    def render(self, text):
        """The announcement as a WAV file (cached by its text); returns the path."""
        key = hashlib.sha1(f"{text}|{voicelines.SENTENCE_GAP_S}|{voicelines.COMMA_GAP_S}".encode()).hexdigest()[:16]
        path = self.dir / "said" / f"{key}.wav"
        if not path.exists():
            self._write(path, self.announcement(text))
        return path

    def export(self, progress=False):
        """Every piece the engine can say, as AAC for git; pieces it no longer
        says are removed, so the repo holds exactly the current set."""
        wanted = voicelines.pieces()
        out = EXPORTED / self.voice
        out.mkdir(parents=True, exist_ok=True)
        t0, made = time.time(), 0
        for n, p in enumerate(wanted, 1):
            if self.exported(p).exists():
                continue
            self.piece(p)
            aac(self._piece_path(p), self.exported(p))
            made += 1
            if progress and made % 25 == 0:
                log(f"  {self.voice}: {n}/{len(wanted)} ({time.time() - t0:.0f} s)")
        keep = {f"{slug(p)}.m4a" for p in wanted}
        stale = [f for f in out.glob("*.m4a") if f.name not in keep]
        for f in stale:
            f.unlink()
        if progress:
            log(f"  {self.voice}: {len(wanted)} pieces exported ({made} new, {len(stale)} stale removed, "
                f"{time.time() - t0:.0f} s)")

    def sample(self):
        path = self.dir / "sample.wav"
        if not path.exists():
            gap = self.silence(ANNOUNCEMENT_GAP_S)
            parts = []
            for i, text in enumerate(voicelines.SAMPLE):
                if i:
                    parts.append(gap)
                parts.append(self.announcement(text))
            self._write(path, self.np.concatenate(parts))
        return path

    def exported(self, p):
        return EXPORTED / self.voice / f"{slug(p)}.m4a"

    def prewarm(self, stop=None, progress=False, extra=()):
        # Exported pieces (in git) need no WAV: the range screen plays those.
        # extra: more pieces the web app will want (the commentary's lines).
        wanted = list(dict.fromkeys(voicelines.pieces() + [voicelines.piece(p) for p in extra if voicelines.piece(p)]))
        todo = [p for p in wanted
                if not self._piece_path(p).exists() and not self.exported(p).exists()]
        t0 = time.time()
        for n, p in enumerate(todo, 1):
            if stop is not None and stop.is_set():
                return
            self.piece(p)
            if progress:
                log(f"  {n}/{len(todo)} {p!r} ({time.time() - t0:.0f} s)")
        if progress:
            log(f"  {self.voice}: all {len(wanted)} pieces cached")


def serve(voice):
    v = Voice(voice)
    stop = threading.Event()
    threading.Thread(target=v.prewarm, kwargs={"stop": stop}, daemon=True).start()
    print(json.dumps({"ready": voice}), flush=True)
    for line in sys.stdin:
        try:
            req = json.loads(line)
            print(json.dumps({"id": req.get("id"), "wav": str(v.render(req["text"]))}), flush=True)
        except Exception as e:                 # never die on one bad line
            print(json.dumps({"id": None, "error": f"{type(e).__name__}: {e}"}), flush=True)
    stop.set()


def main():
    p = argparse.ArgumentParser(description="Spotter's Kokoro announcer voice")
    p.add_argument("command", choices=["serve", "prewarm", "export", "sample", "samples", "say", "piece", "list"])
    p.add_argument("text", nargs="?")
    p.add_argument("--voice", default=voicelines.DEFAULT_VOICE)
    p.add_argument("--all", action="store_true", help="export: every voice")
    p.add_argument("--extra", default=None, help="prewarm: a file of more pieces, one per line")
    a = p.parse_args()
    if a.command == "list":
        print(json.dumps(voicelines.VOICES))
    elif a.command == "serve":
        serve(a.voice)
    elif a.command == "prewarm":
        extra = Path(a.extra).read_text().splitlines() if a.extra else ()
        Voice(a.voice).prewarm(progress=True, extra=extra)
        if a.extra:
            Path(a.extra).unlink(missing_ok=True)
    elif a.command == "export":                 # the known pieces, as AAC for git (web/public/voice-pieces)
        for v in (voicelines.VOICES if a.all else [a.voice]):
            Voice(v).export(progress=True)
    elif a.command == "sample":
        print(Voice(a.voice).sample())
    elif a.command == "samples":                # every voice's sample, for the picker
        import shutil
        import subprocess
        SAMPLES.mkdir(parents=True, exist_ok=True)
        for v in voicelines.VOICES:
            t = time.time()
            wav = Voice(v).sample()
            log(f"  {v}: {wav} ({time.time() - t:.0f} s)")
            # The copy kept in git (32 kbps AAC, ~80 KB): macOS's afconvert.
            if shutil.which("afconvert"):
                subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "32000",
                                str(wav), str(SAMPLES / f"{v}.m4a")], check=True)
    elif a.command == "piece":                  # for the web app: one piece, cached; path printed
        v, piece = Voice(a.voice), voicelines.piece(a.text or "")
        if not piece:
            raise SystemExit("piece: no text")
        v.piece(piece)
        print(v._piece_path(piece))
    elif a.command == "say":
        import subprocess
        subprocess.run(["afplay", str(Voice(a.voice).render(a.text or "ready"))])


if __name__ == "__main__":
    main()
