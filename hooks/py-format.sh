#!/usr/bin/env bash
#
# ai-factory Claude Code hook — Python file formatter.
#
# Wired as a PostToolUse hook on Edit|Write. Runs ruff format + ruff check
# on the changed file if it's a .py or .pyi file. Silent on success.
#
# Requires: ruff in PATH (fast, single-binary formatter+linter for Python
# dev envs). Falls back to no-op if unavailable — we don't block edits on a
# missing formatter.

set -euo pipefail

# Fail open if jq is missing — hooks must never break tool calls on tooling gaps.
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

FILE_PATH=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Normalize to an absolute path. Defensive against a relative path that could
# become invalid if the hook's cwd shifts in the future.
FILE_PATH="$(readlink -f "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")"

case "$FILE_PATH" in
  *.py|*.pyi)
    ;;
  *)
    exit 0
    ;;
esac

if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

if ! command -v ruff >/dev/null 2>&1; then
  # Ruff not installed — skip silently. Don't block edits.
  exit 0
fi

ruff format --quiet "$FILE_PATH" 2>&1 || {
  echo "ruff format failed on $FILE_PATH" >&2
  exit 1
}

# Fix auto-fixable lint issues. Do not fail on remaining lint — those need
# human attention but shouldn't block an edit.
ruff check --fix --quiet "$FILE_PATH" 2>&1 || true
