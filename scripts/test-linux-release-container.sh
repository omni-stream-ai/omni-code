#!/usr/bin/env bash
set -euo pipefail

# These are desktop platform services and graphics drivers, not the GTK,
# WebKit, PulseAudio or ALSA libraries that the application must carry.
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y --no-install-recommends \
  ca-certificates python3 binutils xauth xvfb xdotool dbus-x11 passwd util-linux \
  libgl1 libegl1 libgbm1 libdrm2 libegl-mesa0 libglx-mesa0 libgl1-mesa-dri fonts-dejavu-core
useradd --create-home smoke
release_dir="$(mktemp -d)"
tar -xzf /packages/omni-code-linux-x86_64.tar.gz -C "$release_dir"
chmod 755 "$release_dir"
bundle="$release_dir/omni-code-linux-x86_64"
python3 /checks/verify-linux-bundle.py "$bundle"
runuser -u smoke -- bash /checks/smoke-test-linux.sh "$bundle/AppRun"
runuser -u smoke -- bash /checks/smoke-test-linux.sh /packages/omni-code-linux-x86_64.AppImage
