#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common.sh"

require_cmd gh
require_cmd python3
require_cmd git

checkout_local="false"
args=()
for arg in "$@"; do
  if [[ "$arg" == "--checkout" ]]; then
    checkout_local="true"
  else
    args+=("$arg")
  fi
done

if [[ ${#args[@]} -lt 1 || ${#args[@]} -gt 2 ]]; then
  echo "Usage: $0 <issue-number> [branch-name] [--checkout]" >&2
  exit 1
fi

issue_number="${args[0]}"
branch_name="${args[1]:-}"
metadata_json="$(issue_metadata_json "$issue_number")"

issue_id="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["repository"]["issue"]["id"])' <<<"$metadata_json")"
issue_title="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["repository"]["issue"]["title"])' <<<"$metadata_json")"
issue_url="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["repository"]["issue"]["url"])' <<<"$metadata_json")"
repository_id="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["repository"]["id"])' <<<"$metadata_json")"
base_oid="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["repository"]["defaultBranchRef"]["target"]["oid"])' <<<"$metadata_json")"
label_names="$(python3 -c 'import json,sys; nodes=json.load(sys.stdin)["data"]["repository"]["issue"]["labels"]["nodes"]; print(",".join(label["name"] for label in nodes))' <<<"$metadata_json")"

if [[ -z "$branch_name" ]]; then
  prefix="work"
  case ",${label_names}," in
    *,feature,*) prefix="feat" ;;
    *,bug,*) prefix="fix" ;;
    *,docs,*) prefix="docs" ;;
    *,test,*) prefix="test" ;;
    *,infra,*) prefix="chore" ;;
    *,refactor,*) prefix="refactor" ;;
  esac
  branch_name="${prefix}/${issue_number}-$(slugify "$issue_title")"
fi

gh api graphql -f query='
mutation($issueId: ID!, $oid: GitObjectID!, $name: String!, $repositoryId: ID!) {
  createLinkedBranch(input: {issueId: $issueId, oid: $oid, name: $name, repositoryId: $repositoryId}) {
    linkedBranch {
      ref {
        name
      }
    }
  }
}
' -F issueId="$issue_id" -F oid="$base_oid" -F name="$branch_name" -F repositoryId="$repository_id" >/dev/null

git fetch origin "$branch_name"

if [[ "$checkout_local" == "true" ]]; then
  if git show-ref --verify --quiet "refs/heads/${branch_name}"; then
    git switch "$branch_name"
  else
    git switch -c "$branch_name" --track "origin/${branch_name}"
  fi
fi

project_item_id="$(find_project_item_id_by_issue_number "$issue_number")"
set_single_select_value "$project_item_id" "Status" "In Progress"

echo "Started issue work:"
echo "  issue: #${issue_number}"
echo "  url: ${issue_url}"
echo "  linked_branch: ${branch_name}"
echo "  local_fetch: origin/${branch_name}"
echo "  local_checkout: ${checkout_local}"
