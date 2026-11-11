#!/bin/sh
# Stands in for `python phase1.py locate --json --watch ...` in specs: two results, then end.
R='"found": true, "view_deg": 26.0, "edge_rms_px": 0.41, "perspective": true, "ring_rms_mm": 0.11, "rings": 10, "flat_worst_mm": -0.08, "flat_worst_at": [7, 225], "mm_per_px": 0.197, "ring1_offscreen": [], "brightness": 66.8, "saturated_pct": 0.0'
echo '{"type": "start", "camera": "1", "seconds": 120}'
echo "{\"type\": \"result\", \"seq\": 1, \"remaining\": 119, \"sharpness\": 640.2, $R}"
echo "{\"type\": \"result\", \"seq\": 2, \"remaining\": 118, \"sharpness\": 772.0, $R}"
echo '{"type": "end", "results": 2}'
