#!/usr/bin/env bash
#
# SessionStart hook — injects the using-aif meta-skill into every new
# session, surfacing the skills/agents/references intent map so Claude can
# route work without the human invoking /catalog.
#
# Two install paths:
#   1. install.sh symlinks this into ~/.claude/aif-hooks/. Per-repo
#      settings.json wraps invocation with `if [ -x ... ]; then ... fi` so a
#      fresh clone never blocks session start. Skill resolution path:
#      $SCRIPT_DIR/../skills/using-aif/SKILL.md — hooks/ sits at the repo
#      root and skills live under skills/ (which ~/.claude/skills symlinks).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
META_SKILL="$SCRIPT_DIR/../skills/using-aif/SKILL.md"

if ! command -v jq >/dev/null 2>&1; then
  echo '{"priority": "INFO", "message": "ai-factory: jq not found — skipping meta-skill injection. Install jq (apt-get/brew install jq) to enable."}'
  exit 0
fi

if [[ ! -f "$META_SKILL" ]]; then
  echo '{"priority": "INFO", "message": "ai-factory: using-aif meta-skill not found at expected path — skipping injection."}'
  exit 0
fi

CONTENT=$(cat "$META_SKILL")

# SessionStart contract: context is injected via
# hookSpecificOutput.additionalContext (plain stdout also works, but the
# structured form is explicit and survives schema tightening).
jq -cn \
  --arg ctx "ai-factory toolkit loaded. Use the routing table below to pick the right skill/agent/MCP tool. References load on demand from references/.

$CONTENT" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
