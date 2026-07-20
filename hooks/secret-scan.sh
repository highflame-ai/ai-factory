#!/usr/bin/env bash
#
# ai-factory Claude Code hook — secret scanner on Bash commands.
#
# Wired as a PreToolUse hook on Bash. Inspects the command about to run for
# accidental secret exposure (echo/printf of env vars that look like secrets,
# pasted API keys, JWT dumps). Exits non-zero to block the command if a
# pattern matches.
#
# This is a guardrail, not a comprehensive scanner. It blocks the most common
# footguns during development sessions.

set -euo pipefail

# Fail open if jq is missing — hooks must never break tool calls on tooling gaps.
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

COMMAND=$(jq -r '.tool_input.command // empty')

if [[ -z "$COMMAND" ]]; then
  exit 0
fi

# Patterns that suggest a secret is being printed or logged.
SECRET_PATTERNS=(
  # Env vars with secret-y names being printed
  'echo[[:space:]]+.*\$\{?(SECRET|TOKEN|PASSWORD|API_KEY|PRIVATE_KEY|CREDENTIALS|JWT_SECRET|POSTGRES_PASSWORD)'
  'printf[[:space:]]+.*\$\{?(SECRET|TOKEN|PASSWORD|API_KEY|PRIVATE_KEY|CREDENTIALS|JWT_SECRET|POSTGRES_PASSWORD)'

  # Looks like a committed private key content
  'BEGIN[[:space:]]+(RSA[[:space:]]+)?PRIVATE[[:space:]]+KEY'

  # AWS credentials
  'AKIA[0-9A-Z]{16}'

  # Common vendor secret-key shapes (Stripe/Clerk-style sk_live_/sk_test_,
  # GitHub tokens, Slack tokens, OpenAI/Anthropic-style keys)
  'sk_(live|test)_[a-zA-Z0-9]{24,}'
  '(^|[^[:alnum:]])gh[pousr]_[A-Za-z0-9]{36,}'
  '(^|[^[:alnum:]])xox[baprs]-[A-Za-z0-9-]{10,}'
  '(^|[^[:alnum:]])sk-[A-Za-z0-9_-]{32,}'

  # Add your org's own key prefixes here (e.g. 'acme_sk_[a-zA-Z0-9]{16,}')
)

for pat in "${SECRET_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -qE "$pat"; then
    cat >&2 <<EOF
secret-scan hook blocked a Bash command.

Matched pattern: $pat
Command: $COMMAND

If this is a false positive, edit the hook in
ai-factory/hooks/secret-scan.sh or bypass with:
  /permissions — add a specific allow for this exact command
EOF
    exit 2
  fi
done

# Block obvious destructive patterns that rarely have a good reason.
# (Force-push to protected branches should be gated server-side by your
# forge's branch protection; we don't duplicate that here.)
DESTRUCTIVE_PATTERNS=(
  'rm[[:space:]]+-rf[[:space:]]+/([[:space:]]|$)'
  'rm[[:space:]]+-rf[[:space:]]+/(bin|boot|dev|etc|home|lib|opt|sbin|sys|usr|var|Applications|Library|System|Users)([[:space:]/]|$)'
  'rm[[:space:]]+-rf[[:space:]]+\$HOME'
  'DROP[[:space:]]+DATABASE'
  'DROP[[:space:]]+SCHEMA'
  'TRUNCATE[[:space:]]+TABLE'
)

for pat in "${DESTRUCTIVE_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -qiE "$pat"; then
    cat >&2 <<EOF
secret-scan hook blocked a destructive Bash command.

Matched pattern: $pat
Command: $COMMAND

If you're certain this is intended, run it directly in a terminal instead of
through Claude Code, or add a narrow allow via /permissions.
EOF
    exit 2
  fi
done

# All clean.
exit 0
