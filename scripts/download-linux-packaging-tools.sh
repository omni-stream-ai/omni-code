#!/usr/bin/env bash
set -euo pipefail

tools_dir="${1:-build/linux/packaging-tools}"
mkdir -p "$tools_dir"

# Pin both binaries and plugin sources; do not let a moving continuous release
# silently change the dependency policy of an existing client version.
curl --fail --silent --show-error --location --retry 3 \
  https://github.com/linuxdeploy/linuxdeploy/releases/download/1-alpha-20251107-1/linuxdeploy-x86_64.AppImage \
  --output "$tools_dir/linuxdeploy"
printf '%s  %s\n' \
  c20cd71e3a4e3b80c3483cef793cda3f4e990aca14014d23c544ca3ce1270b4d \
  "$tools_dir/linuxdeploy" | sha256sum --check -
curl --fail --silent --show-error --location --retry 3 \
  https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/7a3fbc31a9e5075073ff8790f26effbac5f84453/linuxdeploy-plugin-gtk.sh \
  --output "$tools_dir/linuxdeploy-plugin-gtk.sh"
curl --fail --silent --show-error --location --retry 3 \
  https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gstreamer/432af639725bc8b99df12351e86bb2e8a6b3585f/linuxdeploy-plugin-gstreamer.sh \
  --output "$tools_dir/linuxdeploy-plugin-gstreamer.sh"
chmod +x "$tools_dir"/linuxdeploy*
