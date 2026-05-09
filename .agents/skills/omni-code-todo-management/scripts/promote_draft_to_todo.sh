#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common.sh"

require_cmd gh
require_cmd python3

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <project-item-id-or-exact-title> [labels]" >&2
  echo "Example labels: feature or bug,infra" >&2
  exit 1
fi

item_token="$1"
labels_csv="${2:-}"
item_id="$(resolve_project_item_id "$item_token")"

repo_json="$(repository_metadata_json)"
repository_id="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["repository"]["id"])' <<<"$repo_json")"

convert_json="$(
  gh api graphql -f query='
mutation($itemId: ID!, $repositoryId: ID!) {
  convertProjectV2DraftIssueItemToIssue(input: {itemId: $itemId, repositoryId: $repositoryId}) {
    item {
      id
      content {
        ... on Issue {
          number
          title
          url
        }
      }
    }
  }
}
' -F itemId="$item_id" -F repositoryId="$repository_id"
)"

issue_number="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["convertProjectV2DraftIssueItemToIssue"]["item"]["content"]["number"])' <<<"$convert_json")"
issue_url="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["convertProjectV2DraftIssueItemToIssue"]["item"]["content"]["url"])' <<<"$convert_json")"

if [[ -n "$labels_csv" ]]; then
  gh issue edit "$issue_number" --repo "$REPO_SLUG" --add-label "$labels_csv" >/dev/null
fi

set_single_select_value "$item_id" "Status" "Todo"

echo "Promoted draft to Todo:"
echo "  issue: #${issue_number}"
echo "  url: ${issue_url}"
if [[ -n "$labels_csv" ]]; then
  echo "  labels: ${labels_csv}"
fi
