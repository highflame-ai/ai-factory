#!/usr/bin/env bash
#
# ai-factory Claude Code hook — TypeScript/JavaScript file formatter.
#
# Wired as a PostToolUse hook on Edit|Write. Runs prettier on the changed file
# if it's a .ts/.tsx/.js/.jsx file. Silent on success.
#
# Requires: prettier available in the file's own project (via pnpm or a
# project-local npx install). Never network-installs a formatter.

set -euo pipefail

# Fail open if jq is missing — hooks must never break tool calls on tooling gaps.
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

FILE_PATH=$(jq -r '.tool_input.file_path // empty')

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Normalize to an absolute path up front. Claude Code's Edit/Write tools
# require absolute file_path, so in practice this is a no-op — but it's
# defensive against any downstream `cd` changing what the relative path
# would resolve to. readlink -f also resolves symlinks consistently.
FILE_PATH="$(readlink -f "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")"

case "$FILE_PATH" in
  *.ts|*.tsx|*.js|*.jsx|*.json|*.md)
    ;;
  *)
    exit 0
    ;;
esac

if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

# Find the nearest package.json — formatting only applies inside a JS/TS
# project that has opted into prettier. Outside one (e.g. a README.md in a Go
# repo), do nothing: never network-install a formatter or rewrite files in
# projects that never asked for it.
DIR=$(dirname "$FILE_PATH")
while [[ "$DIR" != "/" ]]; do
  if [[ -f "$DIR/package.json" ]]; then
    break
  fi
  DIR=$(dirname "$DIR")
done

if [[ ! -f "$DIR/package.json" ]]; then
  exit 0
fi

if command -v pnpm >/dev/null 2>&1 && (cd "$DIR" && pnpm exec prettier --version >/dev/null 2>&1); then
  (cd "$DIR" && pnpm exec prettier --write "$FILE_PATH" 2>&1) || {
    echo "prettier failed on $FILE_PATH" >&2
    exit 1
  }
elif command -v npx >/dev/null 2>&1; then
  # --no-install: use the project's own prettier only; never fetch from npm.
  (cd "$DIR" && npx --no-install prettier --write "$FILE_PATH" 2>/dev/null) || exit 0
else
  # No formatter available — silent pass, don't fail the edit.
  exit 0
fi
