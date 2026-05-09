#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common.sh"

require_cmd gh
require_cmd python3

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <title> <body> [priority]" >&2
  exit 1
fi

title="$1"
body="$2"
priority="${3:-}"

if [[ -n "$priority" ]]; then
  case "$priority" in
    High|Medium|Low) ;;
    *)
      echo "Priority must be one of: High, Medium, Low" >&2
      exit 1
      ;;
  esac
fi

result="$(
  gh project item-create "$PROJECT_NUMBER" \
    --owner "$OWNER" \
    --title "$title" \
    --body "$body" \
    --format json
)"

item_id="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<<"$result")"

set_single_select_value "$item_id" "Status" "Backlog"
if [[ -n "$priority" ]]; then
  set_single_select_value "$item_id" "Priority" "$priority"
fi

echo "Created backlog draft:"
echo "  item_id: ${item_id}"
echo "  title: ${title}"
if [[ -n "$priority" ]]; then
  echo "  priority: ${priority}"
fi
