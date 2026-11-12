#!/bin/sh
# Sets up Spotter's announcer voice (Kokoro) in engine/voice: its own Python 3.13
# environment (Kokoro's dependencies have no builds for newer Pythons yet) and
# the model (~350 MB, not in git). Safe to run again.
#   brew install python@3.13 && engine/voice/setup.sh
set -e
cd "$(dirname "$0")"
PY=${PYTHON:-$(command -v python3.13 || echo /opt/homebrew/bin/python3.13)}
[ -x "$PY" ] || { echo "needs Python 3.13: brew install python@3.13"; exit 1; }
[ -d .venv ] || "$PY" -m venv .venv
.venv/bin/pip install -q -r requirements.txt
mkdir -p models
for f in kokoro-v1.0.onnx voices-v1.0.bin; do
  if [ ! -s "models/$f" ]; then
    curl -fL --progress-bar -o "models/$f.partial" \
      "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/$f"
    mv "models/$f.partial" "models/$f"
  fi
done
echo "voice ready: .venv/bin/python speak.py say --voice af_heart \"shot 3. 8.5, high left\""
