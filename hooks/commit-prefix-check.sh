#!/usr/bin/env bash
#
# ai-factory Claude Code hook — commit-message prefix gate.
#
# Wired as a PreToolUse hook on Bash. Inspects any `git commit -m` invocation
# and rejects subjects that won't pass your CI's commit-subject check. This
# catches the mistake locally instead of bouncing through the forge.
#
# The regex is configurable so it can mirror whatever your CI enforces:
#   1. env var AIF_COMMIT_PREFIX_REGEX (highest precedence)
#   2. .aif/config.yml → org.commit_prefix_regex (read when jq+python allow)
#   3. default: Conventional Commits (feat|fix|docs|...), scopes allowed,
#      plus Merge/Revert/Bump/build(deps) machine-generated subjects.

set -euo pipefail

# Allow opt-out via env var. Checked first so bypass never prints the long
# error block, and so a missing dependency on a bypassed shell still no-ops.
if [[ "${CLAUDE_DISABLE_COMMIT_PREFIX_CHECK:-}" == "1" ]]; then
  exit 0
fi

# Fail open if jq is missing — hooks must not block Bash on tooling gaps.
# (The python3 invocation later is similarly tolerant: || true on its subshell.)
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

COMMAND=$(jq -r '.tool_input.command // empty')

if [[ -z "$COMMAND" ]]; then
  exit 0
fi

# The env bypass above cannot fire when the marker is set INSIDE the guarded
# command (PreToolUse hooks run before it, in a separate process), so honor
# the marker appearing in the command string too.
if grep -q 'CLAUDE_DISABLE_COMMIT_PREFIX_CHECK=1' <<< "$COMMAND"; then
  exit 0
fi

# Only inspect git-commit INVOCATIONS. A command that merely MENTIONS
# git-commit inside a heredoc body or quoted string (editing docs, tests,
# or this hook itself) is not a commit: strip those regions first.
RESIDUE=$(python3 - "$COMMAND" <<'PYSTRIP' 2>/dev/null || printf '%s' "$COMMAND"
import re, sys
cmd = sys.argv[1]
cmd = re.sub(r"<<-?\s*['\"]?(\w+)['\"]?.*?\n\1\b", "<<HEREDOC", cmd, flags=re.DOTALL)
cmd = re.sub(r"'[^']*'", "''", cmd)
cmd = re.sub(r'"(?:[^"\\\\]|\\\\.)*"', '""', cmd)
print(cmd)
PYSTRIP
)
if ! grep -qE '(^|[^[:alnum:]])git[[:space:]]+commit([[:space:]]|$)' <<< "$RESIDUE"; then
  exit 0
fi

# Skip the editor flow: `git commit` with no -m / -F / -C / -c / --amend --no-edit
# can't be statically validated since the subject is decided in $EDITOR.
# Skip --amend --no-edit explicitly — keeps the existing subject.
if grep -qE -- '--amend[[:space:]]+--no-edit|--no-edit[[:space:]]+--amend' <<< "$COMMAND"; then
  exit 0
fi

# Skip -F file (would need to read the file; keep the hook simple) and -C/-c
# (reuse another commit's message — already validated upstream).
if grep -qE -- '(^|[[:space:]])(-F|--file|-C|--reuse-message|-c|--reedit-message)([[:space:]]|=)' <<< "$COMMAND"; then
  exit 0
fi

# Try to extract the subject from -m. Two common shapes:
#   1. git commit -m "single line subject"
#   2. git commit -m "$(cat <<'EOF'\nSubject line\nbody...\nEOF\n)"
#
# The subject is always the first non-empty line of the -m argument. Pull it
# with python for robustness — bash regex is fragile against nested quoting.
SUBJECT=$(python3 - "$COMMAND" <<'PY' 2>/dev/null || true
import re, sys, shlex

cmd = sys.argv[1]

# Strategy A: heredoc shape — git commit -m "$(cat <<'TAG' ... TAG)"
# The subject is the first non-empty line after the heredoc opener.
m = re.search(r"<<['\"]?(\w+)['\"]?\s*\n(.*?)\n\s*\1\b", cmd, re.DOTALL)
if m:
    body = m.group(2)
    for line in body.splitlines():
        if line.strip():
            print(line.strip())
            sys.exit(0)
    sys.exit(0)

# Strategy B: plain -m "subject" — use shlex to handle nested quoting.
try:
    tokens = shlex.split(cmd, posix=True)
except ValueError:
    sys.exit(0)

# Scan only AFTER the commit invocation tokens: in a compound command like
# `python3 -m pytest && <invocation> -m "fix: x"`, the earlier `-m pytest`
# must not be mistaken for the commit subject (live false positive).
start = 0
for j in range(len(tokens) - 1):
    if tokens[j] == "git" and tokens[j + 1] == "commit":
        start = j + 2
        break

i = start
while i < len(tokens):
    t = tokens[i]
    if t == "-m" or t == "--message":
        if i + 1 < len(tokens):
            arg = tokens[i + 1]
            for line in arg.splitlines():
                if line.strip():
                    print(line.strip())
                    sys.exit(0)
        sys.exit(0)
    # Combined short flags: -m, -am, -sm, -mam, etc. Anything that's a single
    # dash bundle containing 'm'. The value is either glued after the 'm'
    # (e.g. -m"subject", -amsubject) or in the next token (e.g. -am subject).
    if t.startswith("-") and not t.startswith("--") and "m" in t:
        m_idx = t.find("m")
        if m_idx < len(t) - 1:
            arg = t[m_idx + 1:]
        elif i + 1 < len(tokens):
            arg = tokens[i + 1]
        else:
            arg = ""
        for line in arg.splitlines():
            if line.strip():
                print(line.strip())
                sys.exit(0)
        sys.exit(0)
    if t.startswith("--message="):
        arg = t[len("--message="):]
        for line in arg.splitlines():
            if line.strip():
                print(line.strip())
                sys.exit(0)
        sys.exit(0)
    i += 1
PY
)

# If we couldn't extract a subject, don't block — fall back to silent pass.
# (Editor flow, malformed quoting, exotic invocation, etc.)
if [[ -z "$SUBJECT" ]]; then
  exit 0
fi

# Resolve the regex: env override, then project config, then the default.
DEFAULT_REGEX='^((feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([^)]+\))?!?:|Merge|Revert|Bump|build\(deps\))'
CONFIG_REGEX=""
# NOTE: hooks run with cwd = the session's working directory, so this reads the
# .aif/config.yml of the repo the session started in. A commit made into a
# DIFFERENT nested repo mid-session gets that session repo's regex (or the
# default) — use AIF_COMMIT_PREFIX_REGEX to override in that situation.
if [[ -f .aif/config.yml ]]; then
  # Extract commit_prefix_regex scoped to the org: block only (value must be
  # double-quoted or bare; single backslashes — awk does no YAML unescaping).
  CONFIG_REGEX=$(awk '
    /^org:/ { in_org=1; next }
    in_org && /^[^[:space:]#]/ { in_org=0 }
    in_org && /^[[:space:]]+commit_prefix_regex:/ {
      sub(/^[[:space:]]+commit_prefix_regex:[[:space:]]*/, "")
      gsub(/^"|"[[:space:]]*$/, "")
      print; exit
    }' .aif/config.yml 2>/dev/null || true)
  # Ignore unfilled <placeholder> values from the template.
  case "$CONFIG_REGEX" in *"<"*) CONFIG_REGEX="" ;; esac
fi
ALLOWED_REGEX="${AIF_COMMIT_PREFIX_REGEX:-${CONFIG_REGEX:-$DEFAULT_REGEX}}"

if [[ "$SUBJECT" =~ $ALLOWED_REGEX ]]; then
  exit 0
fi

cat >&2 <<EOF
Commit-prefix hook blocked this git commit.

Subject: $SUBJECT

That subject does not match the allowed prefix regex:
  $ALLOWED_REGEX

The regex resolves in this order:
  1. AIF_COMMIT_PREFIX_REGEX env var
  2. .aif/config.yml -> org.commit_prefix_regex
  3. default: Conventional Commits + Merge/Revert/Bump/build(deps)

Fix the subject to match, or if your CI enforces a different convention,
set org.commit_prefix_regex in .aif/config.yml to mirror it.

If you really need to bypass (e.g. running a test commit you'll discard),
unset the hook for one shell:
  CLAUDE_DISABLE_COMMIT_PREFIX_CHECK=1 git commit -m '...'

Full hook: \$HOME/.claude/aif-hooks/commit-prefix-check.sh
EOF

exit 2
