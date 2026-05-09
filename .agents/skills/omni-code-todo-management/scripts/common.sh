#!/usr/bin/env bash
set -euo pipefail

OWNER="omni-stream-ai"
REPO="omni-code"
REPO_SLUG="${OWNER}/${REPO}"
PROJECT_NUMBER="2"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

project_view_json() {
  gh project view "$PROJECT_NUMBER" --owner "$OWNER" --format json
}

project_fields_json() {
  gh project field-list "$PROJECT_NUMBER" --owner "$OWNER" --format json
}

project_items_json() {
  gh project item-list "$PROJECT_NUMBER" --owner "$OWNER" --format json
}

project_id() {
  project_view_json | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])'
}

field_id_by_name() {
  local field_name="$1"
  project_fields_json | python3 -c '
import json
import sys

field_name = sys.argv[1]
data = json.load(sys.stdin)["fields"]
for field in data:
    if field["name"] == field_name:
        print(field["id"])
        raise SystemExit(0)
raise SystemExit(f"Field not found: {field_name}")
' "$field_name"
}

single_select_option_id() {
  local field_name="$1"
  local option_name="$2"
  project_fields_json | python3 -c '
import json
import sys

field_name = sys.argv[1]
option_name = sys.argv[2]
data = json.load(sys.stdin)["fields"]
for field in data:
    if field["name"] != field_name:
        continue
    for option in field.get("options", []):
        if option["name"] == option_name:
            print(option["id"])
            raise SystemExit(0)
    raise SystemExit(f"Option not found for {field_name}: {option_name}")
raise SystemExit(f"Field not found: {field_name}")
' "$field_name" "$option_name"
}

set_single_select_value() {
  local item_id="$1"
  local field_name="$2"
  local option_name="$3"
  local current_project_id
  local current_field_id
  local option_id

  current_project_id="$(project_id)"
  current_field_id="$(field_id_by_name "$field_name")"
  option_id="$(single_select_option_id "$field_name" "$option_name")"

  gh project item-edit \
    --id "$item_id" \
    --field-id "$current_field_id" \
    --project-id "$current_project_id" \
    --single-select-option-id "$option_id" \
    >/dev/null
}

find_project_item_id_by_title() {
  local exact_title="$1"
  project_items_json | python3 -c '
import json
import sys

title = sys.argv[1]
matches = []
for item in json.load(sys.stdin)["items"]:
    if item["title"] == title:
        matches.append(item["id"])

if not matches:
    raise SystemExit(f"No project item found with title: {title}")
if len(matches) > 1:
    raise SystemExit(f"Multiple project items found with title: {title}")
print(matches[0])
' "$exact_title"
}

resolve_project_item_id() {
  local token="$1"
  if [[ "$token" == PVTI_* ]]; then
    printf '%s\n' "$token"
    return 0
  fi
  find_project_item_id_by_title "$token"
}

find_project_item_id_by_issue_number() {
  local issue_number="$1"
  project_items_json | python3 -c '
import json
import sys

issue_number = int(sys.argv[1])
for item in json.load(sys.stdin)["items"]:
    content = item.get("content", {})
    if content.get("type") == "Issue" and content.get("number") == issue_number:
        print(item["id"])
        raise SystemExit(0)
raise SystemExit(f"No project item found for issue #{issue_number}")
' "$issue_number"
}

repository_metadata_json() {
  gh api graphql -f query='
query($owner: String!, $repo: String!) {
  repository(owner: $owner, name: $repo) {
    id
    defaultBranchRef {
      name
      target {
        ... on Commit {
          oid
        }
      }
    }
  }
}
' -F owner="$OWNER" -F repo="$REPO"
}

issue_metadata_json() {
  local issue_number="$1"
  gh api graphql -f query='
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    id
    defaultBranchRef {
      name
      target {
        ... on Commit {
          oid
        }
      }
    }
    issue(number: $number) {
      id
      number
      title
      url
      labels(first: 20) {
        nodes {
          name
        }
      }
    }
  }
}
' -F owner="$OWNER" -F repo="$REPO" -F number="$issue_number"
}

slugify() {
  local value="$1"
  python3 - "$value" <<'PY'
import re
import sys
import unicodedata

value = unicodedata.normalize("NFKD", sys.argv[1]).encode("ascii", "ignore").decode("ascii")
value = value.lower()
value = re.sub(r"[^a-z0-9]+", "-", value).strip("-")
value = re.sub(r"-{2,}", "-", value)
print(value or "work-item")
PY
}
