#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${DISPLAY:-}" ]]; then
  exec xvfb-run -a "$0" "$@"
fi
smoke_state="$(mktemp -d)"
export XDG_CONFIG_HOME="$smoke_state/config"
export XDG_DATA_HOME="$smoke_state/data"
export XDG_CACHE_HOME="$smoke_state/cache"
export LIBGL_ALWAYS_SOFTWARE=1
export APPIMAGE_EXTRACT_AND_RUN=1
export NO_AT_BRIDGE=1

"$@" >"$smoke_state/launch.log" 2>&1 &
app_pid=$!
# Cleanup is invoked indirectly by the EXIT trap.
# shellcheck disable=SC2329
cleanup() {
  kill "$app_pid" 2>/dev/null || true
  wait "$app_pid" 2>/dev/null || true
  rm -rf -- "$smoke_state"
}
trap cleanup EXIT

# The GTK runner maps its window only after Flutter renders its first frame.
for ((attempt = 0; attempt < 120; attempt++)); do
  if ! kill -0 "$app_pid" 2>/dev/null; then
    cat "$smoke_state/launch.log" >&2
    printf 'The Linux client exited before rendering its first frame.\n' >&2
    exit 1
  fi
  if xdotool search --onlyvisible --class 'omni_code|com[.]omnistreamai[.]code' >/dev/null 2>&1; then
    printf 'The Linux client rendered a visible window.\n'
    exit 0
  fi
  sleep 0.25
done
cat "$smoke_state/launch.log" >&2
printf 'The Linux client did not render a visible window within 30 seconds.\n' >&2
exit 1
