#!/usr/bin/env bash
#
# Stop reflection hook — at session end, captures any non-obvious gotcha
# the session uncovered into an inbox file for later review/promotion to
# ~/.claude/aif-references/known-warts.md.
#
# Mechanism:
#   - Stop hook receives JSON on stdin: { transcript_path, cwd, session_id,
#     stop_hook_active, … }
#   - We count meaningful tool uses (Edit + Write) in the transcript. If
#     fewer than AIF_REFLECT_MIN_EDITS (default 3), exit silently —
#     trivial sessions aren't worth a reflection pass.
#   - If substantial AND stop_hook_active is false (avoids infinite reflect
#     loops), emit a Stop-hook JSON response that sends Claude back for ONE
#     reflection turn with a tight, capped prompt.
#   - Claude appends a one-line entry to the inbox if anything notable, or
#     no-ops if not. The inbox lives at:
#       ~/.claude/aif-references/known-warts-inbox.md
#     (~/.claude/aif-references is symlinked to the toolkit's references/
#     directory by install.sh; the inbox file is created on first append).
#   - A per-session marker file makes this fire AT MOST ONCE per session:
#     Stop hooks run every time Claude finishes responding, not just at
#     "session end", so without the marker the reflection prompt would repeat
#     on every turn after the edit threshold is crossed.
#
# Disable:
#   - Per-session:    AIF_REFLECT_OFF=1 claude
#   - Per-repo:       add { "env": { "AIF_REFLECT_OFF": "1" } } to .claude/settings.local.json
#   - Per-developer:  export AIF_REFLECT_OFF=1 in ~/.bashrc / ~/.zshrc
#
# This hook NEVER blocks a Stop unless reflection is desired. On any unexpected
# error it exits 0 silently — Claude proceeds to stop normally.

set -euo pipefail

# ── Read & guard ──────────────────────────────────────────────────────────────

if [[ "${AIF_REFLECT_OFF:-}" == "1" ]]; then
  exit 0
fi

# Stop hook input on stdin; read once into a variable
INPUT=$(cat || true)
if [[ -z "$INPUT" ]]; then
  exit 0
fi

# jq is required to parse hook input. If missing, no-op (don't block stop).
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# Avoid infinite loops: if this hook already fired for this stop, exit clean.
STOP_HOOK_ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false')
if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then
  exit 0
fi

TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')

if [[ -z "$TRANSCRIPT_PATH" || ! -f "$TRANSCRIPT_PATH" ]]; then
  exit 0
fi

# Fire at most once per session: Stop hooks run after EVERY response, so mark
# the session the first time we trigger and no-op thereafter.
if [[ -n "$SESSION_ID" ]]; then
  MARKER="${TMPDIR:-/tmp}/aif-reflect-${SESSION_ID}"
  if [[ -e "$MARKER" ]]; then
    exit 0
  fi
fi

# ── Substance check ───────────────────────────────────────────────────────────
# Count Edit + Write tool uses. Skim only the transcript line count (~MB) — jq
# over a multi-line JSONL stream is the most reliable parse.

MIN_EDITS="${AIF_REFLECT_MIN_EDITS:-3}"

# Each transcript line is a JSON object; assistant tool_use messages have
# .message.content[].type == "tool_use" with .name in {Edit, Write, …}.
# Stream via `jq -n 'inputs'` so we don't load multi-MB transcripts into memory.
EDIT_COUNT=$(jq -n '
  [inputs
    | select(.type == "assistant")
    | .message.content[]?
    | select(.type == "tool_use")
    | select(.name == "Edit" or .name == "Write" or .name == "NotebookEdit")
  ] | length
' "$TRANSCRIPT_PATH" 2>/dev/null || echo 0)

if [[ -z "$EDIT_COUNT" || "$EDIT_COUNT" -lt "$MIN_EDITS" ]]; then
  exit 0
fi

# ── Repo context ──────────────────────────────────────────────────────────────
REPO_NAME="$(basename "$CWD" 2>/dev/null || echo unknown)"
TODAY="$(date +%Y-%m-%d)"

# Resolve the inbox path. Prefer the user-level symlink target (consistent
# across worktrees); fall back to an in-tree path under the current repo's
# references/ directory if the symlink isn't set up yet (e.g., install.sh
# hasn't run on this machine).
INBOX_DEFAULT="$HOME/.claude/aif-references/known-warts-inbox.md"
INBOX_FALLBACK="$CWD/references/known-warts-inbox.md"
INBOX="${AIF_REFLECT_INBOX:-$INBOX_DEFAULT}"
if [[ ! -d "$(dirname "$INBOX")" ]]; then
  INBOX="$INBOX_FALLBACK"
fi

# ── Emit reflection prompt ────────────────────────────────────────────────────
# Claude Code accepts JSON on stdout with decision="block" + reason — the
# reason is fed back to Claude as a fresh assistant turn. We keep it tight so
# Claude doesn't spend more than ~1k tokens on this pass.

REASON="REFLECTION CHECK — this session edited $EDIT_COUNT files in $REPO_NAME. Did anything in this session reveal a NON-OBVIOUS gotcha or platform wart that the next engineer (or your next Claude session) would benefit from knowing — something the code/docs don't tell you? Examples: a CI gate that's silently broken, a contract that diverges from naming intuition, a test that's deterministically skipped, a env-var/flag whose absence causes confusing failures.

If YES: append ONE LINE to $INBOX in this exact format (create the file if missing):
\`\`\`
$TODAY | $REPO_NAME | <one-line wart> | <one-line what to do or why it matters>
\`\`\`
APPEND (do not overwrite) the line. If the file exists, read it first and write back existing + new line, or use a bash >> redirect. Do NOT call Write with only the new line — it will wipe prior entries. Do not edit the canonical ~/.claude/aif-references/known-warts.md — only the inbox. Then stop.

If NO: just say \"no wart this session\" and stop. Do not summarize what we did — the diff and PR description already do that.

Cap your reflection at ~150 words. Do not re-engage on the prior task."

# Mark the session as reflected BEFORE emitting, so a crash after emit can't
# cause a repeat. Marker creation failing is not fatal (worst case: one repeat).
if [[ -n "$SESSION_ID" ]]; then
  touch "$MARKER" 2>/dev/null || true
fi

# Emit JSON to stdout. Claude Code reads this and re-invokes the model with the
# reason as the next user turn (with stop_hook_active = true so we don't loop).
jq -nc \
  --arg reason "$REASON" \
  '{decision: "block", reason: $reason}'
