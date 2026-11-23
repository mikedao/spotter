#!/bin/bash
# Set up the Pi at the target: ON THE PI, from this folder:   sudo ./install.sh
# Safe to re-run (after a git pull, or with a new camera).
#  - ustreamer streams the camera on :8080 (spotter-camera.service), on boot
#  - the camera's tuned settings (cameras/<vendor>-<product>.conf, by
#    engine/camtune.py) are applied on every stream start and camera plug-in
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Run it with sudo:  sudo ./install.sh"; exit 1; }
U=${SUDO_USER:-}
[ -n "$U" ] && [ "$U" != root ] || { echo "Run it with sudo from your own login, not as root."; exit 1; }
cd "$(dirname "$0")"

need=()
command -v ustreamer >/dev/null || need+=(ustreamer)
command -v v4l2-ctl  >/dev/null || need+=(v4l-utils)
if [ ${#need[@]} -gt 0 ]; then apt-get update && apt-get install -y "${need[@]}"; fi
usermod -aG video "$U"

sed "s/YOUR_USER/$U/" spotter-camera.service > /etc/systemd/system/spotter-camera.service
sed "s/YOUR_USER/$U/" spotter-camera-controls.service > /etc/systemd/system/spotter-camera-controls.service
install -m 755 camera-controls.sh /usr/local/bin/spotter-camera-controls
install -m 644 99-spotter-camera.rules /etc/udev/rules.d/99-spotter-camera.rules
# Profiles: owned by you, so camtune.py can install a new one over ssh without sudo.
# One already here (tuned on THIS rig) is kept over the repo's.
install -d -o "$U" -g "$U" /etc/spotter/cameras
for f in cameras/*.conf; do
  [ -e "/etc/spotter/cameras/$(basename "$f")" ] || install -m 644 -o "$U" -g "$U" "$f" /etc/spotter/cameras/
done

udevadm control --reload
systemctl daemon-reload
systemctl enable spotter-camera >/dev/null
systemctl restart spotter-camera
sleep 5

echo
v4l2-ctl --list-devices 2>/dev/null | grep -A1 -i usb || echo "! no USB camera found - plug it in (it starts by itself)"
journalctl -u spotter-camera-controls -n 3 --no-pager -o cat 2>/dev/null | tail -2
echo
echo "Stream:  http://$(hostname).local:8080/stream   (the app's camera step)"
echo "Tune a camera with no settings yet, from the laptop with a clean card up:"
echo "  ssh-copy-id $U@$(hostname).local        # once"
echo "  cd engine && ./.venv/bin/python camtune.py --pi $U@$(hostname).local"
