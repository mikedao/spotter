#!/bin/sh
# Stands in for a camera check that dies mid-watch (no "end" line): one result,
# an error on stderr, then killed by a signal, as a native crash would be.
echo '{"type": "start", "camera": "http://pi:8080/stream", "seconds": 120}'
echo '{"type": "result", "seq": 1, "remaining": 119, "found": false, "reason": "no target"}'
echo "cv2.error: stream read failed" >&2
kill -SEGV $$
