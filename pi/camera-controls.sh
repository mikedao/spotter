#!/bin/sh
# Spotter: the C920's settings, from the 2026-11-23 sweep on the rig (pi/README.md).
# Run on every camera plug-in (udev) and every stream start: a C920 forgets its
# settings when it loses power, and ustreamer reopens a replugged camera on its
# own, so a setting applied only when the service starts is lost on a replug.
# ONE control per v4l2-ctl call (several in one call broke the Kiyo's frames), and
# the auto switches BEFORE the values they guard (a manual value is ignored while
# its auto is on).
DEV=/dev/video0
sleep 3   # let ustreamer open the camera and start streaming first
for c in \
  focus_automatic_continuous=0 focus_absolute=30 \
  auto_exposure=1 exposure_dynamic_framerate=0 exposure_time_absolute=666 gain=40 \
  white_balance_automatic=0 white_balance_temperature=4970 \
  power_line_frequency=2
do
  v4l2-ctl -d "$DEV" -c "$c" || echo "spotter-camera-controls: could not set $c"
done
v4l2-ctl -d "$DEV" --get-ctrl=focus_absolute,exposure_time_absolute,gain,white_balance_temperature
