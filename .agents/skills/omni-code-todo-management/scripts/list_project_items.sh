#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common.sh"

require_cmd gh
require_cmd python3

status_filter="${1:-}"
json="$(project_items_json)"

python3 -c '
import json
import sys

status_filter = sys.argv[1]
data = json.load(sys.stdin)["items"]

rows = []
for item in data:
    status = item.get("status", "")
    if status_filter and status != status_filter:
        continue
    priority = item.get("priority", "")
    content = item.get("content", {})
    item_type = content.get("type", "Unknown")
    issue_number = content.get("number", "")
    title = item.get("title", "")
    rows.append((status, priority, item_type, str(issue_number), title))

if not rows:
    print("No project items matched.")
    raise SystemExit(0)

headers = ("Status", "Priority", "Type", "Issue", "Title")
widths = [len(h) for h in headers]
for row in rows:
    for idx, value in enumerate(row):
        widths[idx] = max(widths[idx], len(value))

def format_row(values):
    return "  ".join(value.ljust(widths[idx]) for idx, value in enumerate(values))

print(format_row(headers))
print(format_row(tuple("-" * width for width in widths)))
for row in rows:
    print(format_row(row))
' "$status_filter" <<<"$json"
