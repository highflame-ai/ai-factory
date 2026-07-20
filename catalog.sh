#!/usr/bin/env bash
#
# ai-factory — catalog of available subagents, skills, and hooks.
#
# Prints a scannable list of everything currently installed, plus how to
# invoke each one. Safe to run anytime.
#
# Usage:
#   /Workspace/ai-factory/catalog.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

# Extract the YAML frontmatter `description:` value from an agent/skill file.
# Tolerates optional leading whitespace before the key (defensive — we author
# flat frontmatter by convention, but YAML permits indentation).
get_desc() {
  awk '/^[[:space:]]*description:/ {
    sub(/^[[:space:]]*description:[[:space:]]*/, "", $0)
    print
    exit
  }' "$1"
}

echo
echo -e "${BOLD}==> ai-factory — available tools${NC}"
echo
echo -e "${DIM}Source:${NC} $SCRIPT_DIR"
echo -e "${DIM}Update:${NC} cd \"$SCRIPT_DIR\" && git pull"
echo

# ---- subagents --------------------------------------------------------------

echo -e "${BOLD}${BLUE}Subagents${NC} — delegate specialized review/analysis"
echo -e "${DIM}Invoke three ways:${NC}"
echo -e "  1. By name:         ${CYAN}\"Have the security-reviewer audit this PR.\"${NC}"
echo -e "  2. With @-mention:  ${CYAN}\"@security-reviewer audit this PR.\"${NC}"
echo -e "  3. Natural phrase:  ${CYAN}\"Check this code for auth bugs.\"${NC} (Claude picks the right agent)"
echo -e "  Live list in session: type ${CYAN}/agents${NC}"
echo

for agent in "$SCRIPT_DIR"/agents/*.md; do
  [[ -e "$agent" ]] || continue
  name="$(basename "$agent" .md)"
  desc="$(get_desc "$agent")"
  printf "  ${GREEN}%-22s${NC} %s\n" "$name" "$desc"
done

echo

# ---- skills -----------------------------------------------------------------

echo -e "${BOLD}${BLUE}Skills${NC} — choreographed multi-step workflows"
echo -e "${DIM}Invoke two ways:${NC}"
echo -e "  1. Slash command:   ${CYAN}/spec${NC}"
echo -e "  2. Natural phrase:  ${CYAN}\"Write a spec for this feature request.\"${NC}"
echo

for skill_md in "$SCRIPT_DIR"/skills/*/SKILL.md; do
  [[ -e "$skill_md" ]] || continue
  name="$(basename "$(dirname "$skill_md")")"
  desc="$(get_desc "$skill_md")"
  printf "  ${GREEN}/%-21s${NC} %s\n" "$name" "$desc"
done

echo

# ---- hooks ------------------------------------------------------------------

echo -e "${BOLD}${BLUE}Hooks${NC} — fire automatically; no invocation needed"
echo

for hook in "$SCRIPT_DIR"/hooks/*.sh; do
  [[ -e "$hook" ]] || continue
  name="$(basename "$hook")"
  # Extract first non-shebang, non-empty comment line as description.
  desc="$(awk '
    /^#!/ { next }
    /^#[^!]/ { sub(/^# */, "", $0); if ($0) { print; exit } }
    /^$/ { next }
  ' "$hook")"
  printf "  ${GREEN}%-22s${NC} %s\n" "$name" "$desc"
done

echo

# ---- references -------------------------------------------------------------

if compgen -G "$SCRIPT_DIR/references/*.md" > /dev/null; then
  echo -e "${BOLD}${BLUE}References${NC} — load on demand from skills/agents (not auto-loaded)"
  echo -e "${DIM}Read via:${NC} ${CYAN}Read references/<file>.md${NC} (from the repo root, or ~/.claude/aif-references/)"
  echo

  for ref in "$SCRIPT_DIR"/references/*.md; do
    [[ -e "$ref" ]] || continue
    name="$(basename "$ref")"
    [[ "$name" == "README.md" ]] && continue
    # First non-empty line after the H1 is the lead — extract it.
    desc="$(awk '
      /^# / { found_h1 = 1; next }
      found_h1 && NF > 0 { print; exit }
    ' "$ref")"
    printf "  ${GREEN}%-36s${NC} %s\n" "$name" "$desc"
  done

  echo
fi

# ---- bin/ helpers -----------------------------------------------------------

if compgen -G "$SCRIPT_DIR/bin/*.sh" > /dev/null; then
  echo -e "${BOLD}${BLUE}Sidecar scripts${NC} — invoked by agents/skills, not directly by users"
  echo -e "${DIM}Resolved via ${CYAN}\$HOME/.claude/aif-bin/${NC}"
  echo

  for helper in "$SCRIPT_DIR"/bin/*.sh; do
    [[ -e "$helper" ]] || continue
    name="$(basename "$helper")"
    desc="$(awk '
      /^#!/ { next }
      /^#[^!]/ { sub(/^# */, "", $0); if ($0) { print; exit } }
      /^$/ { next }
    ' "$helper")"
    printf "  ${GREEN}%-30s${NC} %s\n" "$name" "$desc"
  done

  echo
fi

# ---- reference links --------------------------------------------------------

echo -e "${BOLD}${BLUE}More${NC}"
echo -e "  README:           ${CYAN}$SCRIPT_DIR/README.md${NC}"
echo -e "  Tips for Claude:  ${CYAN}$SCRIPT_DIR/tips.md${NC}"
echo -e "  Workspace CLAUDE: ${CYAN}$SCRIPT_DIR/workspace-CLAUDE.md${NC} (loads in every session)"
echo
