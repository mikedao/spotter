#!/bin/sh
# Stands in for `python phase1.py pinpoint ... --out DIR` in specs: the hole is at
# (-9.0, 3.0) mm; writes the two close-ups to DIR.
out=""
while [ $# -gt 0 ]; do [ "$1" = "--out" ] && out="$2"; shift; done
printf 'fake-jpeg' > "$out/closeup_after.jpg"
printf 'fake-jpeg' > "$out/closeup_before.jpg"
echo '{"found": true, "x_mm": -9.0, "y_mm": 3.0, "closeup": {"centre": [-9.0, 3.0], "px_per_mm": 20.0, "size_px": 480}}'
