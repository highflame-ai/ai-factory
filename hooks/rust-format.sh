#!/usr/bin/env bash
#
# ai-factory Claude Code hook — Rust file formatter.
#
# Wired as a PostToolUse hook on Edit|Write. Runs rustfmt on the changed file
# if it's a .rs file. Silent on success.
#
# Requires: rustfmt in PATH (ships with rustup). Falls back to no-op if
# unavailable — we don't block edits on a missing formatter.
#
# Edition: assumes edition 2021+ projects; rustfmt reads rustfmt.toml if present.
# If a future Rust crate moves to 2024, update the --edition arg below.

set -euo pipefail

# Fail open if jq is missing — hooks must never break tool calls on tooling gaps.
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

FILE_PATH=$(jq -r '.tool_input.file_path // empty')

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

FILE_PATH="$(readlink -f "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")"

if [[ "$FILE_PATH" != *.rs ]]; then
  exit 0
fi

if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

if ! command -v rustfmt >/dev/null 2>&1; then
  exit 0
fi

if ! rustfmt --edition 2021 "$FILE_PATH" 2>&1; then
  echo "rustfmt failed on $FILE_PATH — check formatting errors above." >&2
  exit 1
fi
