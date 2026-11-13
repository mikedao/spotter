#!/bin/sh
# Sets up the hole locator's training environment in engine/ml (Python 3.13 +
# PyTorch). The engine never needs it: it runs the exported model with cv2.dnn.
#   brew install python@3.13 && engine/ml/setup.sh
set -e
cd "$(dirname "$0")"
PY=${PYTHON:-$(command -v python3.13 || echo /opt/homebrew/bin/python3.13)}
[ -x "$PY" ] || { echo "needs Python 3.13: brew install python@3.13"; exit 1; }
[ -d .venv ] || "$PY" -m venv .venv
.venv/bin/pip install -q -r requirements.txt
echo "ready: cd engine && ml/.venv/bin/python ml/train.py"
