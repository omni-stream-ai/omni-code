#!/usr/bin/env bash
set -euo pipefail

version="${1:?version required}"
archive="${2:?Linux archive path required}"
package_file="${3:-nix/omni-code-bin.nix}"

if [[ ! -f "$archive" ]]; then
  echo "Linux archive not found: $archive" >&2
  exit 1
fi

if [[ ! -f "$package_file" ]]; then
  echo "Nix package file not found: $package_file" >&2
  exit 1
fi

hash="sha256-$(openssl dgst -sha256 -binary "$archive" | openssl base64 -A)"

sed -i -E \
  -e "s|version = \"[^\"]+\";|version = \"${version}\";|" \
  -e "s|hash = \"sha256-[^\"]+\";|hash = \"${hash}\";|" \
  "$package_file"

echo "Updated $package_file to $version ($hash)"
