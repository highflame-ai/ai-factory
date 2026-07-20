#!/usr/bin/env bash
#
# ai-factory — distribute shared .claude/settings.json to every repo in the
# workspace matching AIF_REPO_GLOB (default: every git repo beside this one).
#
# Strategy:
#   - If the repo has no .claude/settings.json → write the shared one as-is.
#   - If the repo already has one → merge with jq:
#       * Union the existing + shared permissions.allow (deduplicated, sorted)
#       * Replace permissions.deny with the shared deny list (security policy
#         is authoritative across the fleet — per-repo deny customization
#         goes in .claude/settings.local.json, not the shared file)
#       * Replace hooks block entirely (shared hooks are the source of truth)
#       * Back up the original to .claude/settings.json.before-shared-rollout
#
# Hook scripts themselves are NOT distributed per-repo. They live in
# ai-factory/hooks/, exposed via the
# ~/.claude/aif-hooks/ symlink that install.sh creates. settings.json's
# hook commands are wrapped with `if [ -x ... ]; then ...; fi` so a fresh
# clone where install.sh hasn't run yet still works (hooks no-op silently
# instead of blocking Bash). This keeps the fleet's settings.json stable
# across hook script updates — change a hook in ai-factory and
# every dev picks it up on their next git pull, no per-repo PRs needed.
#
# Idempotent — safe to re-run. Re-running after edits to the shared
# settings.example.json refreshes every repo's hooks block + permissions.
#
# Usage:
#   <workspace>/ai-factory/tools/fleet/distribute-settings.sh        # distribute to all
#   <workspace>/ai-factory/tools/fleet/distribute-settings.sh api    # only the "api" repo
#   <workspace>/ai-factory/tools/fleet/distribute-settings.sh -n     # dry-run
#
# After running, `cd` into each repo that changed and commit the result so
# the team gets the settings on their next `git pull`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# This script lives at <repo>/tools/fleet/ — the repo root is two levels up.
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SHARED_SETTINGS="$REPO_ROOT/skills/templates/settings.example.json"
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

if ! command -v jq >/dev/null 2>&1; then
  err "jq is required. Install it first."
  exit 1
fi

if [[ ! -f "$SHARED_SETTINGS" ]]; then
  err "Shared settings not found: $SHARED_SETTINGS"
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
  warn "Dry-run mode — no files will be written."
fi

# -- find candidate repos -----------------------------------------------------

if [[ -n "$FILTER" ]]; then
  # The filter argument is the repo directory name under the workspace.
  target_name="$FILTER"
  REPOS=("$WORKSPACE/$target_name")
else
  # Every git repo beside this one (narrow with AIF_REPO_GLOB, e.g. 'acme-*').
  REPO_GLOB="${AIF_REPO_GLOB:-*}"
  # bash-3.2 compatible (macOS system bash has no mapfile).
  WORKSPACE="${WORKSPACE%/}"
  REPOS=()
  while IFS= read -r _repo; do
    [ -n "$_repo" ] && REPOS+=("$_repo")
  done < <(find "$WORKSPACE" -mindepth 1 -maxdepth 1 -type d -name "$REPO_GLOB" \
    ! -path "$REPO_ROOT" -exec test -e '{}/.git' \; -print | sort)
fi

if [[ ${#REPOS[@]} -eq 0 ]]; then
  err "No matching git repos found under $WORKSPACE (glob: ${AIF_REPO_GLOB:-*})"
  exit 1
fi

info "Found ${#REPOS[@]} candidate repo(s)."
echo

# -- merge function -----------------------------------------------------------

# Produces the merged settings JSON on stdout.
#   $1 = existing settings.json path
merge_settings() {
  local existing="$1"
  # Start from the EXISTING file and overlay only what this rollout owns:
  # $schema/_comment, the allow union, the shared deny list, and the shared
  # hooks block. Everything else the repo has set (permissions.ask,
  # defaultMode, env, model, ...) is preserved untouched.
  jq -s '
    .[0] as $shared |
    .[1] as $existing |
    $existing
    | .["$schema"] = $shared["$schema"]
    | ._comment    = $shared._comment
    | .permissions = (
        ($existing.permissions // {}) + {
          "allow": (
            (($existing.permissions.allow // []) + ($shared.permissions.allow // []))
            | unique
            | sort
          ),
          "deny": ($shared.permissions.deny // [])
        }
      )
    | .hooks = $shared.hooks
  ' "$SHARED_SETTINGS" "$existing"
}

# -- distribute ---------------------------------------------------------------

skipped=0
written=0
merged=0
unchanged=0

for repo in "${REPOS[@]}"; do
  name=$(basename "$repo")

  if [[ ! -d "$repo/.git" ]]; then
    skip "$name (not a git repo)"
    skipped=$((skipped + 1))
    continue
  fi

  target="$repo/.claude/settings.json"

  if [[ -f "$target" ]]; then
    # Existing — merge.
    tmp_merged="$(mktemp)"
    merge_settings "$target" > "$tmp_merged"

    if diff -q "$target" "$tmp_merged" >/dev/null 2>&1; then
      ok "$name: already up to date"
      unchanged=$((unchanged + 1))
      rm -f "$tmp_merged"
      continue
    fi

    if [[ "$DRY_RUN" == "yes" ]]; then
      info "$name: would merge (existing allow entries preserved)"
      echo "    diff preview:"
      diff "$target" "$tmp_merged" | head -20 | sed 's/^/    /'
      rm -f "$tmp_merged"
      continue
    fi

    backup="$target.before-shared-rollout.$(date +%Y%m%d-%H%M%S)"
    cp "$target" "$backup"
    mv "$tmp_merged" "$target"
    ok "$name: merged (original backed up to $(basename "$backup"))"
    merged=$((merged + 1))
  else
    # New.
    if [[ "$DRY_RUN" == "yes" ]]; then
      info "$name: would write new .claude/settings.json"
      continue
    fi
    mkdir -p "$repo/.claude"
    cp "$SHARED_SETTINGS" "$target"
    ok "$name: written"
    written=$((written + 1))
  fi
done

echo
echo "==> Summary"
printf "    Written (new):  %d\n" "$written"
printf "    Merged:         %d\n" "$merged"
printf "    Unchanged:      %d\n" "$unchanged"
printf "    Skipped:        %d\n" "$skipped"

if [[ "$DRY_RUN" == "no" ]] && (( written + merged > 0 )); then
  cat <<EOF

Next step: commit the new/merged settings.json in each affected repo.

  for repo in $(printf '"%s" ' "${REPOS[@]}"); do
    if [ -n "\$(cd \"\$repo\" && git status --porcelain .claude/settings.json 2>/dev/null)" ]; then
      echo "=== \$(basename \$repo) ==="
      (cd "\$repo" && git diff --stat .claude/settings.json)
    fi
  done
EOF
fi
