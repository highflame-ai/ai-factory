#!/usr/bin/env bash
#
# ai-factory Claude Code hook — Go file formatter.
#
# Wired as a PostToolUse hook on Edit|Write. Runs gofmt on the changed file if
# it's a .go file. Silent on success; prints errors so Claude can see them.
#
# Install: referenced from settings.example.json. Not invoked directly.

set -euo pipefail

# Fail open if jq is missing — hooks must never break tool calls on tooling gaps.
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# Claude Code passes the hook input as JSON on stdin. Pipe directly to jq
# rather than capturing into a variable + echo — avoids `echo` interpreting
# backslashes in file paths and skips an extra process per fire.
FILE_PATH=$(jq -r '.tool_input.file_path // empty')

if [[ -z "$FILE_PATH" ]]; then
  # No file path — nothing to format, exit clean.
  exit 0
fi

# Normalize to an absolute path. Defensive against a relative path that could
# become invalid if the hook's cwd shifts in the future.
FILE_PATH="$(readlink -f "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")"

# Only format Go files.
if [[ "$FILE_PATH" != *.go ]]; then
  exit 0
fi

if [[ ! -f "$FILE_PATH" ]]; then
  # File was deleted or moved; nothing to format.
  exit 0
fi

# gofmt writes in-place with -w. Silent on success.
if ! gofmt -w "$FILE_PATH" 2>&1; then
  echo "gofmt failed on $FILE_PATH — check formatting errors above." >&2
  exit 1
fi

# goimports is optional but preferred for Go files that rearrange imports.
if command -v goimports >/dev/null 2>&1; then
  goimports -w "$FILE_PATH" 2>&1 || true
fi
