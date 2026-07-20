#!/usr/bin/env bash
#
# ai-factory — open a PR in every repo whose .claude/settings.json
# was modified by distribute-settings.sh.
#
# Workflow per repo:
#   1. Verify working tree is clean except for .claude/settings.json
#   2. Save current branch, switch to default branch (main/master), pull latest
#   3. Create branch: chore/adopt-shared-claude-settings
#   4. Re-apply the .claude/settings.json change
#   5. Commit, push -u origin <branch>
#   6. Open PR via gh pr create
#   7. Return to the originally-checked-out branch
#
# Requires: git, gh (GitHub CLI, authenticated).
#
# Usage:
#   ./open-settings-prs.sh            # open PRs in every modified repo
#   ./open-settings-prs.sh -n         # dry-run: print what would happen
#   ./open-settings-prs.sh api        # only the "api" repo
#
# Safety:
#   - Refuses to proceed if the working tree has changes to files OTHER than
#     .claude/settings.json (we won't bundle unrelated work into your PR).
#   - Skips repos where the branch already exists remotely (likely a PR is
#     already open — avoids clobbering it).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# This script lives at <repo>/tools/fleet/ — the repo root is two levels up.
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# --- workspace root resolution -----------------------------------------------
# The workspace is the directory containing your org's repos. Never assumed
# blindly: resolution order is
#   1. AIF_WORKSPACE env var
#   2. ~/.claude/aif/config.yml -> workspace.root
#   3. default: the parent directory of this toolkit clone
resolve_workspace() {
  default_ws="$1"
  if [ -n "${AIF_WORKSPACE:-}" ]; then
    printf '%s\n' "$AIF_WORKSPACE"
    return 0
  fi
  cfg="$HOME/.claude/aif/config.yml"
  if [ -f "$cfg" ]; then
    w=$(awk '
      /^workspace:/ { in_w=1; next }
      in_w && /^[^[:space:]#]/ { in_w=0 }
      in_w && /^[[:space:]]+root:/ {
        sub(/^[[:space:]]+root:[[:space:]]*/, "")
        # Quoted value: take what is inside the quotes. Bare value: strip a
        # trailing inline "# comment" and trailing whitespace.
        if ($0 ~ /^\"/) { sub(/^\"/, ""); sub(/\".*$/, "") }
        else { sub(/[[:space:]]+#.*$/, ""); sub(/[[:space:]]+$/, "") }
        print; exit
      }' "$cfg" 2>/dev/null)
    case "$w" in
      "~/"*) w="$HOME/${w#"~/"}" ;;
    esac
    case "$w" in
      ""|*"<"*) : ;;                 # unset or unfilled placeholder
      *) printf '%s\n' "$w"; return 0 ;;
    esac
  fi
  printf '%s\n' "$default_ws"
}

WORKSPACE="$(resolve_workspace "$(dirname "$REPO_ROOT")")"

BRANCH_NAME="${BRANCH_NAME:-chore/adopt-shared-claude-settings}"
COMMIT_MSG="chore: adopt shared Claude Code settings from ai-factory"
PR_TITLE="chore: adopt shared Claude Code settings from ai-factory"
PR_BODY="Adopt the team-wide \`.claude/settings.json\` distributed from \`ai-factory/\`.

## What this changes

- **\`permissions.allow\`** — union of existing entries with the shared safe-command baseline (Go, TS, Python, Make, Docker, common git operations). Nothing removed.
- **\`permissions.deny\`** — shared deny list (blocks \`rm -rf /\`, \`git push --force main\`, etc.)
- **\`hooks\`** — point at the shared scripts in \`ai-factory/hooks/\`:
    - PostToolUse on Edit|Write: \`gofmt\`/\`goimports\`, \`prettier\`, \`ruff format\`+\`ruff check --fix\`, \`rustfmt\` (auto-dispatched by file extension)
    - PreToolUse on Bash: secret-scan + destructive-command block

## Source of truth

- Shared settings: [\`ai-factory/skills/templates/settings.example.json\`](https://github.com/<owner>/ai-factory/blob/main/skills/templates/settings.example.json)
- Distributed via: [\`ai-factory/distribute-settings.sh\`](https://github.com/<owner>/ai-factory/blob/main/distribute-settings.sh)
- Docs: [\`ai-factory/README.md\`](https://github.com/<owner>/ai-factory/blob/main/README.md)

Per-developer overrides go in \`.claude/settings.local.json\` (git-ignored) — not this file.
"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
DIM='\033[2m'
NC='\033[0m'

info()  { echo -e "${BLUE}[info]${NC}   $1"; }
ok()    { echo -e "${GREEN}[ok]${NC}     $1"; }
warn()  { echo -e "${YELLOW}[warn]${NC}   $1"; }
err()   { echo -e "${RED}[err]${NC}    $1"; }
skip()  { echo -e "${DIM}[skip]${NC}   $1"; }

# -- deps ---------------------------------------------------------------------

for cmd in git gh; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    err "Missing dependency: $cmd"
    err "Install git + the GitHub CLI (https://cli.github.com) and run 'gh auth login'."
    exit 1
  fi
done

# Verify gh is authenticated.
if ! gh auth status >/dev/null 2>&1; then
  err "gh is not authenticated. Run 'gh auth login' first."
  exit 1
fi

# -- args ---------------------------------------------------------------------

DRY_RUN="no"
FILTER=""

for arg in "$@"; do
  case "$arg" in
    -n|--dry-run)
      DRY_RUN="yes"
      ;;
    -h|--help)
      sed -n '/^# Usage:/,/^#$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      err "Unknown flag: $arg"
      exit 1
      ;;
    *)
      FILTER="$arg"
      ;;
  esac
done

if [[ "$DRY_RUN" == "yes" ]]; then
  warn "Dry-run mode — no branches, commits, pushes, or PRs will be created."
fi

# -- find candidate repos -----------------------------------------------------

if [[ -n "$FILTER" ]]; then
  target_name="$FILTER"
  REPOS=("$WORKSPACE/$target_name")
else
  REPO_GLOB="${AIF_REPO_GLOB:-*}"
  # bash-3.2 compatible (macOS system bash has no mapfile).
  WORKSPACE="${WORKSPACE%/}"
  REPOS=()
  while IFS= read -r _repo; do
    [ -n "$_repo" ] && REPOS+=("$_repo")
  done < <(find "$WORKSPACE" -mindepth 1 -maxdepth 1 -type d -name "$REPO_GLOB" \
    ! -path "$REPO_ROOT" -exec test -e '{}/.git' \; -print | sort)
fi

# -- per-repo PR function -----------------------------------------------------

open_pr_for_repo() {
  local repo="$1"
  local name
  name="$(basename "$repo")"

  if [[ ! -d "$repo/.git" ]]; then
    skip "$name: not a git repo"
    return 2
  fi

  # Is there a .claude/settings.json diff?
  local settings_status
  settings_status="$(cd "$repo" && git status --porcelain .claude/settings.json 2>/dev/null || true)"

  if [[ -z "$settings_status" ]]; then
    skip "$name: no pending changes to .claude/settings.json"
    return 2
  fi

  # Are there other unrelated uncommitted changes?
  local other_changes
  other_changes="$(cd "$repo" && git status --porcelain 2>/dev/null | grep -v '^.. \.claude/settings\.json$' | grep -v '^.. \.claude/settings\.json\.before-shared-rollout\.' || true)"

  if [[ -n "$other_changes" ]]; then
    warn "$name: working tree has unrelated changes — skipping to avoid bundling:"
    echo "$other_changes" | sed 's/^/      /'
    warn "      Commit or stash the unrelated changes, then re-run on just this repo:"
    warn "      $(basename "${BASH_SOURCE[0]}") $name"
    return 2
  fi

  # Determine default branch (main or master).
  local default_branch
  default_branch="$(cd "$repo" && git remote show origin 2>/dev/null | awk '/HEAD branch/ {print $NF}' || true)"
  if [[ -z "$default_branch" ]]; then
    # Fall back to main if we can't detect.
    default_branch="main"
    warn "$name: could not detect default branch — falling back to 'main'"
  fi

  # Current branch — we'll restore it after the PR is created.
  local current_branch
  current_branch="$(cd "$repo" && git rev-parse --abbrev-ref HEAD)"

  # Already a remote branch with our name? Someone may have an open PR already.
  if (cd "$repo" && git ls-remote --exit-code --heads origin "$BRANCH_NAME" >/dev/null 2>&1); then
    warn "$name: remote branch '$BRANCH_NAME' already exists — likely an open PR. Skipping."
    return 2
  fi

  if [[ "$DRY_RUN" == "yes" ]]; then
    info "$name: would create branch '$BRANCH_NAME' from '$default_branch', commit .claude/settings.json, push, open PR"
    echo "      current branch: $current_branch"
    echo "      default branch: $default_branch"
    return 0
  fi

  info "$name: opening PR..."

  # Preserve the settings change by copying it aside. A stash cannot represent
  # the most common case here — a brand-new (untracked) settings.json makes
  # `git stash create` return empty — and this rollout only ever touches the
  # one file, so a plain copy is both simpler and correct for every case.
  local settings_tmp
  settings_tmp="$(mktemp)"
  cp "$repo/.claude/settings.json" "$settings_tmp"

  # Reset the working tree: restore the tracked version if one exists, remove
  # the file if it was untracked (fresh adoption).
  if (cd "$repo" && git ls-files --error-unmatch .claude/settings.json >/dev/null 2>&1); then
    (cd "$repo" && git checkout -- .claude/settings.json 2>/dev/null || true)
  else
    rm -f "$repo/.claude/settings.json"
  fi

  # Switch to default branch + pull.
  if ! (cd "$repo" && git checkout "$default_branch" 2>/dev/null); then
    err "$name: could not checkout '$default_branch' — aborting"
    mkdir -p "$repo/.claude" && cp "$settings_tmp" "$repo/.claude/settings.json"
    rm -f "$settings_tmp"
    return 1
  fi
  (cd "$repo" && git pull --ff-only origin "$default_branch" 2>/dev/null) || {
    warn "$name: 'git pull' failed (network? non-ff?) — continuing with local $default_branch"
  }

  # Create the PR branch.
  (cd "$repo" && git checkout -b "$BRANCH_NAME")

  # Re-apply the settings change.
  mkdir -p "$repo/.claude"
  cp "$settings_tmp" "$repo/.claude/settings.json"
  rm -f "$settings_tmp"

  # Stage + commit only .claude/settings.json (defensive).
  (cd "$repo" && git add .claude/settings.json)
  (cd "$repo" && git commit -m "$COMMIT_MSG" >/dev/null)

  # Push.
  if ! (cd "$repo" && git push -u origin "$BRANCH_NAME" 2>&1 | tail -5); then
    err "$name: git push failed"
    (cd "$repo" && git checkout "$current_branch" 2>/dev/null || true)
    return 1
  fi

  # Open PR.
  local pr_url
  if pr_url="$(cd "$repo" && gh pr create --title "$PR_TITLE" --body "$PR_BODY" --base "$default_branch" 2>&1)"; then
    ok "$name: PR opened → $(echo "$pr_url" | tail -1)"
  else
    err "$name: gh pr create failed: $pr_url"
  fi

  # Restore the originally-checked-out branch.
  (cd "$repo" && git checkout "$current_branch" 2>/dev/null || true)
}

# -- main ---------------------------------------------------------------------

opened=0
skipped=0
failed=0

# open_pr_for_repo return codes: 0 = PR opened, 2 = nothing to do (skipped),
# anything else = failed.
for repo in "${REPOS[@]}"; do
  if open_pr_for_repo "$repo"; then
    opened=$((opened + 1))
  else
    status=$?
    if [[ "$status" -eq 2 ]]; then
      skipped=$((skipped + 1))
    else
      failed=$((failed + 1))
    fi
  fi
done

echo
echo "==> Done. opened=$opened skipped=$skipped failed=$failed"
echo "    Review PRs at: gh pr list --author @me --state open"
