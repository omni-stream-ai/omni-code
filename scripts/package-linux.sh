#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
bundle="$(realpath "${1:-$project_dir/build/linux/x64/release/bundle}")"
dist="$(realpath -m "${2:-$project_dir/dist}")"
tools_dir="$(realpath "${LINUX_PACKAGING_TOOLS:-$project_dir/build/linux/packaging-tools}")"
stage="$dist/omni-code-linux-x86_64"

if [[ ! -x "$bundle/omni_code" || ! -x "$tools_dir/linuxdeploy" ]]; then
  printf 'Build the Linux Release bundle and run scripts/download-linux-packaging-tools.sh first.\n' >&2
  exit 1
fi
if [[ "$(patchelf --print-interpreter "$bundle/omni_code")" == /nix/store/* ]]; then
  printf 'Build portable releases on the Ubuntu CI baseline. Nix builds use the project flake.\n' >&2
  exit 1
fi
if [[ "$bundle" == "$stage" || "$bundle" == "$stage/"* || "$stage" == "$bundle/"* ]]; then
  printf 'The input bundle and packaging destination must not overlap.\n' >&2
  exit 1
fi
mkdir -p "$dist"
rm -rf -- "$stage"
mkdir -p "$stage/usr/bin" "$stage/usr/libexec/webkit2gtk-4.1"
# Flutter plugins can install symlinks into the build tree. The published
# archive must contain the files themselves, never links back to that tree.
cp -RL "$bundle/." "$stage/"
install -m755 "$project_dir/scripts/linux/AppRun" "$stage/AppRun"
install -m644 "$project_dir/LICENSE" "$stage/LICENSE"
ln -s ../../AppRun "$stage/usr/bin/omni-code"
mkdir -p "$stage/usr/share/alsa"
cp -RL "$(pkg-config --variable=prefix alsa)/share/alsa/." "$stage/usr/share/alsa/"
mkdir -p "$stage/etc/fonts"
cp -RL "$(pkg-config --variable=confdir fontconfig)/." "$stage/etc/fonts/"

webkit_libdir="$(pkg-config --variable=libdir webkit2gtk-4.1)"
webkit_helpers="$webkit_libdir/webkit2gtk-4.1"
if [[ ! -x "$webkit_helpers/WebKitWebProcess" ]]; then
  webkit_helpers="$(pkg-config --variable=libexecdir webkit2gtk-4.1)"
  if [[ ! -x "$webkit_helpers/WebKitWebProcess" ]]; then
    webkit_helpers="$webkit_helpers/webkit2gtk-4.1"
  fi
fi
if [[ ! -x "$webkit_helpers/WebKitWebProcess" ]]; then
  printf 'WebKit helper processes were not found; refusing to publish an incomplete bundle.\n' >&2
  exit 1
fi
cp -RL "$webkit_helpers/." "$stage/usr/libexec/webkit2gtk-4.1/"
if [[ -d "$webkit_libdir/webkit2gtk-4.1/injected-bundle" && ! -d "$stage/usr/libexec/webkit2gtk-4.1/injected-bundle" ]]; then
  cp -RL "$webkit_libdir/webkit2gtk-4.1/injected-bundle" "$stage/usr/libexec/webkit2gtk-4.1/"
fi

export PATH="$tools_dir:$PATH"
export APPIMAGE_EXTRACT_AND_RUN=1
export DEPLOY_GTK_VERSION=3
export LDAI_OUTPUT="$dist/omni-code-linux-x86_64.AppImage"
export LDAI_RUNTIME_FILE="$dist/.appimage-runtime-x86_64"
# Reuse the runtime from the checksum-pinned linuxdeploy AppImage instead of
# letting appimagetool fetch a moving runtime during the packaging step.
runtime_offset="$(env -u APPIMAGE_EXTRACT_AND_RUN "$tools_dir/linuxdeploy" --appimage-offset)"
head -c "$runtime_offset" "$tools_dir/linuxdeploy" >"$LDAI_RUNTIME_FILE"
export LINUXDEPLOY_OUTPUT_VERSION
LINUXDEPLOY_OUTPUT_VERSION="$(sed -n 's/^version: \([^+]*\).*/\1/p' "$project_dir/pubspec.yaml")"

# ALSA is normally excluded by linuxdeploy as a host library. Explicitly
# include it and PulseAudio so installing audio packages is not a prerequisite.
"$tools_dir/linuxdeploy" \
  --appdir "$stage" \
  --deploy-deps-only "$stage" \
  --library "$(pkg-config --variable=libdir alsa)/libasound.so.2" \
  --library "$(pkg-config --variable=libdir libpulse)/libpulse.so.0" \
  --plugin gtk --plugin gstreamer \
  --desktop-file "$project_dir/nix/omni-code.desktop" \
  --icon-file "$project_dir/web/icons/Icon-512.png" \
  --icon-filename com.omnistreamai.code \
  --custom-apprun "$project_dir/scripts/linux/AppRun"

# linuxdeploy assumes several desktop libraries already exist on the host.
# Explicitly deploy the remaining application closure (including WebKit and
# font libraries), while leaving glibc and GPU drivers to the target system.
python3 "$project_dir/scripts/linux-host-libraries.py" "$stage" >"$dist/.native-libraries"
mapfile -d '' -t host_libraries <"$dist/.native-libraries"
if (( "${#host_libraries[@]}" )); then
  extra_libraries=()
  for library in "${host_libraries[@]}"; do
    extra_libraries+=(--library "$library")
  done
  "$tools_dir/linuxdeploy" --appdir "$stage" "${extra_libraries[@]}"
fi

# Keep hook execution in our launcher. linuxdeploy's generated wrapper runs
# the GTK hook first and would override the desktop's Wayland/X11 selection.
mv "$stage/apprun-hooks" "$stage/omni-code-hooks"
install -m755 "$project_dir/scripts/linux/AppRun" "$stage/AppRun"
rm -f -- "$stage/AppRun.wrapped"

python3 "$project_dir/scripts/verify-linux-bundle.py" "$stage"
"$tools_dir/linuxdeploy" --appdir "$stage" --output appimage
tar -C "$dist" -czf "$dist/omni-code-linux-x86_64.tar.gz" omni-code-linux-x86_64
printf 'Created %s and %s\n' \
  "$dist/omni-code-linux-x86_64.tar.gz" "$LDAI_OUTPUT"
