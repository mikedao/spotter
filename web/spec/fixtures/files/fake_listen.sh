#!/bin/sh
# Stands in for `python phase1.py listen --json ...` in specs: the engine's JSON lines.
echo '{"type": "start", "mic": "Razer Kiyo", "seconds": 5, "trigger_db": 45.0, "trigger_ms": 180.0}'
echo '{"type": "sound", "n": 1, "t": 3.2, "gap_ms": null, "peak_dbfs": -24.0, "over_db": 38.0, "len_ms": 22, "would_trigger": false}'
echo '{"type": "sound", "n": 2, "t": 8.9, "gap_ms": 5700, "peak_dbfs": -1.0, "over_db": 61.3, "len_ms": 330, "would_trigger": true}'
echo '{"type": "end", "silent": false, "events": 2, "floor_dbfs": -61.0, "loudest_dbfs": -1.0}'
