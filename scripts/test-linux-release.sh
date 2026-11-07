#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
dist="$(realpath "${1:-$project_dir/dist}")"
for distribution in ubuntu:22.04 debian:bookworm-slim; do
  docker run --rm \
    --mount "type=bind,src=$dist,dst=/packages,readonly" \
    --mount "type=bind,src=$project_dir/scripts,dst=/checks,readonly" \
    "$distribution" bash /checks/test-linux-release-container.sh
done
