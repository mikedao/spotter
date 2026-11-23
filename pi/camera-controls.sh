#!/bin/sh
# spotter-camera-controls [--now] [DEVICE]: apply the camera's tuned settings.
#
# Looks up the camera's USB id and applies /etc/spotter/cameras/<vendor>-<product>.conf
# (written by engine/camtune.py; the repo's pi/cameras/ are installed there by
# install.sh). A camera with no profile is left on its own automatics.
# Run after every stream start (spotter-camera.service) and every plug-in (the
# udev rule): a webcam like the C920 forgets its settings without power, and
# ustreamer reopens a replugged camera by itself, so settings applied only when
# the service starts are lost (2026-11-23: the C920 came up on autofocus).
# ONE control per v4l2-ctl call (several in one call broke the Kiyo's frames),
# in the profile's order (an auto switch before the value it guards).
NOW=
[ "$1" = "--now" ] && { NOW=1; shift; }
DEV=${1:-/dev/video0}
DIR=${SPOTTER_CAMERA_PROFILES:-/etc/spotter/cameras}
[ -n "$NOW" ] || sleep 3   # let ustreamer open the camera and start streaming
[ -e "$DEV" ] || { echo "spotter-camera-controls: no $DEV"; exit 0; }
prop() { udevadm info -q property -n "$DEV" | sed -n "s/^$1=//p"; }
VID=$(prop ID_VENDOR_ID); PID=$(prop ID_MODEL_ID); NAME=$(prop ID_MODEL)
PROFILE="$DIR/$VID-$PID.conf"
if [ ! -f "$PROFILE" ]; then
  echo "spotter-camera-controls: no settings for $NAME ($VID:$PID) in $DIR -" \
       "it runs on its own automatics. Tune it from the laptop: engine/camtune.py --pi $(hostname).local"
  exit 0
fi
echo "spotter-camera-controls: $NAME ($VID:$PID) <- $PROFILE"
grep -E '^[a-z_]+=-?[0-9]+$' "$PROFILE" | while IFS= read -r c; do
  v4l2-ctl -d "$DEV" -c "$c" || echo "spotter-camera-controls: could not set $c"
done
