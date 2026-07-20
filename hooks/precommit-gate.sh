#!/usr/bin/env bash
#
# ai-factory Claude Code hook — precommit deterministic pre-flight gate.
#
# Wired as a PreToolUse hook on Bash. Intercepts `git commit` invocations and
# runs stack-detected static analysis on the staged files only. Blocks the
# commit if any check fails. Catches the same class of issues CI catches —
# locally, before push, with no LLM tokens spent.
#
# Defaults (always run when relevant files are staged):
#   Go:           gofmt -l (drift), go vet (changed pkgs)
#   Python:       ruff format --check, ruff check (no --fix)
#   TypeScript:   prettier --check, tsc --noEmit (project-wide)
#   Rust:         cargo fmt --check
#
# Skipped by default (slower; opt in via env):
#   AIF_PRECOMMIT_RUN_LINT=1   → golangci-lint, pnpm lint, cargo clippy
#   AIF_PRECOMMIT_RUN_TESTS=1  → go test (changed pkgs), pytest -q
#
# Bypass (one-shell escape hatch):
#   CLAUDE_DISABLE_PRECOMMIT_GATE=1 git commit -m '...'
#
# Fail-open: if jq, git, or any analyzer is missing, the hook no-ops rather
# than blocking. Auto-format hooks (PostToolUse Edit/Write) already keep
# Claude-edited files clean — this gate catches IDE-edited drift and
# non-autofix diagnostics that formatters can't surface.

set -uo pipefail

# ----- bypass + tooling fail-open --------------------------------------------

if [[ "${CLAUDE_DISABLE_PRECOMMIT_GATE:-}" == "1" ]]; then
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

if ! command -v git >/dev/null 2>&1; then
  exit 0
fi

# ----- only inspect git commit invocations -----------------------------------

COMMAND=$(jq -r '.tool_input.command // empty')

if [[ -z "$COMMAND" ]]; then
  exit 0
fi

if ! grep -qE '(^|[^[:alnum:]])git[[:space:]]+commit([[:space:]]|$)' <<< "$COMMAND"; then
  exit 0
fi

# Skip --amend --no-edit (no semantic change to file content).
if grep -qE -- '--amend[[:space:]]+--no-edit|--no-edit[[:space:]]+--amend' <<< "$COMMAND"; then
  exit 0
fi

# ----- locate repo + staged files --------------------------------------------

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$REPO_ROOT"

# Files about to be committed.
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null || true)

# For --amend (without --no-edit), also include the previous commit's files —
# the user may be reworking content, not just the message.
if grep -qE -- '(^|[[:space:]])--amend([[:space:]]|$)' <<< "$COMMAND"; then
  PREV_FILES=$(git show --pretty='' --name-only --diff-filter=ACMR HEAD 2>/dev/null || true)
  STAGED_FILES=$(printf '%s\n%s\n' "$STAGED_FILES" "$PREV_FILES" | sort -u | sed '/^$/d')
fi

if [[ -z "$STAGED_FILES" ]]; then
  exit 0
fi

# ----- failure accumulator ---------------------------------------------------

FAILURES=()
add_failure() {
  FAILURES+=("$1")
}

# ----- Go --------------------------------------------------------------------

GO_FILES=$(printf '%s\n' "$STAGED_FILES" | grep -E '\.go$' || true)
if [[ -n "$GO_FILES" && -f go.mod ]]; then
  # Format drift — files Claude didn't edit (IDE / bare bash) won't have run
  # through the PostToolUse go-format hook.
  if command -v gofmt >/dev/null 2>&1; then
    UNFORMATTED=$(printf '%s\n' "$GO_FILES" | xargs -r gofmt -l 2>/dev/null || true)
    if [[ -n "$UNFORMATTED" ]]; then
      add_failure "gofmt: unformatted files staged
$UNFORMATTED

Fix:
  gofmt -w $(echo "$UNFORMATTED" | tr '\n' ' ')"
    fi
  fi

  # go vet on changed packages only (full ./... is overkill on big repos).
  if command -v go >/dev/null 2>&1; then
    PKGS=$(printf '%s\n' "$GO_FILES" | xargs -r -n1 dirname | sort -u | sed 's|^|./|' | tr '\n' ' ')
    if [[ -n "$PKGS" ]]; then
      VET_OUT=$(go vet $PKGS 2>&1)
      if [[ $? -ne 0 ]]; then
        add_failure "go vet failed:
$VET_OUT"
      fi
    fi
  fi

  # Optional: golangci-lint, scoped to the diff vs origin/main.
  if [[ "${AIF_PRECOMMIT_RUN_LINT:-}" == "1" ]] && command -v golangci-lint >/dev/null 2>&1; then
    LINT_OUT=$(golangci-lint run --new-from-rev=origin/main 2>&1)
    if [[ $? -ne 0 ]]; then
      add_failure "golangci-lint failed:
$LINT_OUT"
    fi
  fi

  # Optional: tests on changed packages.
  if [[ "${AIF_PRECOMMIT_RUN_TESTS:-}" == "1" ]] && command -v go >/dev/null 2>&1 && [[ -n "${PKGS:-}" ]]; then
    TEST_OUT=$(go test $PKGS 2>&1)
    if [[ $? -ne 0 ]]; then
      add_failure "go test failed:
$TEST_OUT"
    fi
  fi
fi

# ----- Python ----------------------------------------------------------------

PY_FILES=$(printf '%s\n' "$STAGED_FILES" | grep -E '\.py$' || true)
if [[ -n "$PY_FILES" ]] && { [[ -f pyproject.toml ]] || [[ -f setup.py ]] || [[ -f requirements.txt ]]; }; then
  if command -v ruff >/dev/null 2>&1; then
    # Format drift — same gap as Go's gofmt above.
    FMT_OUT=$(printf '%s\n' "$PY_FILES" | xargs -r ruff format --check 2>&1)
    if [[ $? -ne 0 ]]; then
      add_failure "ruff format --check failed:
$FMT_OUT

Fix:
  ruff format $(echo "$PY_FILES" | tr '\n' ' ')"
    fi

    # Lint diagnostics (no --fix; py-format hook already applied autofix).
    LINT_OUT=$(printf '%s\n' "$PY_FILES" | xargs -r ruff check 2>&1)
    if [[ $? -ne 0 ]]; then
      add_failure "ruff check failed:
$LINT_OUT"
    fi
  fi

  # Optional: pytest.
  if [[ "${AIF_PRECOMMIT_RUN_TESTS:-}" == "1" ]] && command -v pytest >/dev/null 2>&1; then
    TEST_OUT=$(pytest -q 2>&1)
    if [[ $? -ne 0 ]]; then
      add_failure "pytest failed:
$TEST_OUT"
    fi
  fi
fi

# ----- TypeScript / JavaScript -----------------------------------------------

TS_FILES=$(printf '%s\n' "$STAGED_FILES" | grep -E '\.(ts|tsx|js|jsx|cjs|mjs)$' || true)
if [[ -n "$TS_FILES" && -f package.json ]] && command -v pnpm >/dev/null 2>&1; then
  # prettier --check (drift catch).
  if pnpm exec prettier --version >/dev/null 2>&1; then
    FMT_OUT=$(printf '%s\n' "$TS_FILES" | xargs -r pnpm exec prettier --check 2>&1)
    if [[ $? -ne 0 ]]; then
      add_failure "prettier --check failed:
$FMT_OUT

Fix:
  pnpm exec prettier --write $(echo "$TS_FILES" | tr '\n' ' ')"
    fi
  fi

  # tsc --noEmit — project-wide; can't easily scope. Skipped if no tsconfig.
  if [[ -f tsconfig.json ]] && pnpm exec tsc --version >/dev/null 2>&1; then
    TC_OUT=$(pnpm exec tsc --noEmit 2>&1)
    if [[ $? -ne 0 ]]; then
      add_failure "tsc --noEmit failed:
$TC_OUT"
    fi
  fi

  # Optional: pnpm lint.
  if [[ "${AIF_PRECOMMIT_RUN_LINT:-}" == "1" ]]; then
    if grep -q '"lint"' package.json 2>/dev/null; then
      LINT_OUT=$(pnpm lint 2>&1)
      if [[ $? -ne 0 ]]; then
        add_failure "pnpm lint failed:
$LINT_OUT"
      fi
    fi
  fi
fi

# ----- Rust ------------------------------------------------------------------

RS_FILES=$(printf '%s\n' "$STAGED_FILES" | grep -E '\.rs$' || true)
if [[ -n "$RS_FILES" && -f Cargo.toml ]] && command -v cargo >/dev/null 2>&1; then
  FMT_OUT=$(cargo fmt --check 2>&1)
  if [[ $? -ne 0 ]]; then
    add_failure "cargo fmt --check failed:
$FMT_OUT

Fix:
  cargo fmt"
  fi

  if [[ "${AIF_PRECOMMIT_RUN_LINT:-}" == "1" ]]; then
    CLIPPY_OUT=$(cargo clippy --no-deps -q -- -D warnings 2>&1)
    if [[ $? -ne 0 ]]; then
      add_failure "cargo clippy failed:
$CLIPPY_OUT"
    fi
  fi
fi

# ----- report or pass --------------------------------------------------------

if [[ ${#FAILURES[@]} -eq 0 ]]; then
  exit 0
fi

cat >&2 <<EOF
precommit-gate hook blocked this git commit.

The following deterministic pre-flight checks failed for staged files. Fix
them and re-stage before re-running git commit. These are the same checks
CI runs — catching them locally saves a CI bounce.

EOF

for f in "${FAILURES[@]}"; do
  printf -- '----\n%s\n\n' "$f" >&2
done

cat >&2 <<EOF
----
Bypass for one shell (use sparingly):
  CLAUDE_DISABLE_PRECOMMIT_GATE=1 git commit -m '...'

Opt-in for slower checks:
  AIF_PRECOMMIT_RUN_LINT=1   # also run golangci-lint / pnpm lint / clippy
  AIF_PRECOMMIT_RUN_TESTS=1  # also run go test / pytest

Hook source: \$HOME/.claude/aif-hooks/precommit-gate.sh
EOF

exit 2
