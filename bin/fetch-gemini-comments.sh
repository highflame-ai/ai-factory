#!/usr/bin/env bash
#
# Fetches all gemini-code-assist[bot] comments (review + issue) from a GitHub
# PR and emits a single JSON array. Used by the gemini-reviewer agent.
#
# Usage:
#   fetch-gemini-comments.sh <PR_URL>
#   fetch-gemini-comments.sh <owner/repo> <PR_NUMBER>
#
# Output (stdout):
#   JSON array, each element:
#     {
#       "type":       "review_comment" | "issue_comment",
#       "url":        "<html_url>",
#       "path":       "<file path or null>",
#       "line":       <int or null>,
#       "diff_hunk":  "<context diff or null>",
#       "body":       "<comment markdown>",
#       "created_at": "<iso-8601>",
#       "in_reply_to_id": <int or null>  // review comments only
#     }
#
# Exit codes:
#   0 = success (array may be empty if no gemini comments found)
#   1 = usage/dep error
#   2 = gh API call failed
#
# Environment overrides:
#   BOT_LOGIN  — bot author (default "gemini-code-assist", matches
#                "gemini-code-assist[bot]"). Set to e.g. "Copilot" to fetch
#                a different bot's comments.

set -euo pipefail

for cmd in gh jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "fetch-comments: missing dependency '$cmd'" >&2
    exit 1
  fi
done

if ! gh auth status >/dev/null 2>&1; then
  echo "fetch-comments: gh is not authenticated. Run 'gh auth login'." >&2
  exit 1
fi

BOT_LOGIN="${BOT_LOGIN:-gemini-code-assist}"
BOT_MATCH="${BOT_LOGIN}[bot]"

# -- parse args ---------------------------------------------------------------

OWNER=""
REPO=""
NUMBER=""

case "${1:-}" in
  "")
    echo "Usage: $0 <PR_URL> | <owner/repo> <PR_NUMBER>" >&2
    exit 1
    ;;
  https://github.com/*)
    # https://github.com/owner/repo/pull/123 (optionally followed by /files etc.)
    url="$1"
    # Strip protocol + host, split on /
    path_part="${url#https://github.com/}"
    OWNER="$(echo "$path_part" | awk -F/ '{print $1}')"
    REPO="$(echo "$path_part"  | awk -F/ '{print $2}')"
    # Expect: pull/NN
    third="$(echo "$path_part" | awk -F/ '{print $3}')"
    NUMBER="$(echo "$path_part" | awk -F/ '{print $4}')"
    if [[ "$third" != "pull" || -z "$NUMBER" ]]; then
      echo "fetch-comments: could not parse PR URL: $url" >&2
      exit 1
    fi
    ;;
  */*)
    # owner/repo form + separate PR number
    OWNER="${1%%/*}"
    REPO="${1##*/}"
    NUMBER="${2:-}"
    if [[ -z "$NUMBER" ]]; then
      echo "Usage: $0 <owner/repo> <PR_NUMBER>" >&2
      exit 1
    fi
    ;;
  *)
    echo "Usage: $0 <PR_URL> | <owner/repo> <PR_NUMBER>" >&2
    exit 1
    ;;
esac

# -- fetch both comment types ------------------------------------------------

# Review comments (inline on code). `--paginate` emits concatenated JSON
# arrays; we merge with `jq -s 'add'` to get one flat array.
review_raw="$(
  gh api "repos/$OWNER/$REPO/pulls/$NUMBER/comments" --paginate 2>/dev/null \
    | jq -s 'add // []'
)" || { echo "fetch-comments: failed to fetch review comments" >&2; exit 2; }

# Issue comments (general PR conversation).
issue_raw="$(
  gh api "repos/$OWNER/$REPO/issues/$NUMBER/comments" --paginate 2>/dev/null \
    | jq -s 'add // []'
)" || { echo "fetch-comments: failed to fetch issue comments" >&2; exit 2; }

# -- filter + normalize ------------------------------------------------------

jq -n --arg bot "$BOT_MATCH" \
      --argjson review "$review_raw" \
      --argjson issues "$issue_raw" \
  '
    ($review
      | map(select(.user.login == $bot))
      | map({
          type:           "review_comment",
          url:            .html_url,
          path:           .path,
          line:           (.line // .original_line),
          diff_hunk:      .diff_hunk,
          body:           .body,
          created_at:     .created_at,
          in_reply_to_id: (.in_reply_to_id // null)
        })
    ) + (
      $issues
      | map(select(.user.login == $bot))
      | map({
          type:           "issue_comment",
          url:            .html_url,
          path:           null,
          line:           null,
          diff_hunk:      null,
          body:           .body,
          created_at:     .created_at,
          in_reply_to_id: null
        })
    )
    | sort_by(.created_at)
  '
