# partials/id-alloc.sh — collision-safe id allocation, remote as source of truth (REQ-518).
#
# Source this partial, then call aif_alloc_id WITHIN THE SAME fenced block:
#   . .aif/partials/id-alloc.sh 2>/dev/null || . ~/.claude/skills/partials/id-alloc.sh
#   REQ_NUM=$(aif_alloc_id req)
#   # `exit 1` inside aif_alloc_id's subshell terminates only the subshell — REQ_NUM
#   # would be silently empty. Guard the parent context (REQ-416 verify D-pass).
#   [ -n "$REQ_NUM" ] || { echo "ERROR: failed to allocate REQ number — aborting" >&2; exit 1; }
#
# The three counters (req/bug/lesson) share ONE allocation helper parameterized by
# kind (BR-5), replacing the near-identical inline blocks in /spec, /bugfix, /wrapup.
# Allocation order (BR-1): derive remote high-water -> max(remote, local) -> allocate
# max+1 -> fast-forward the local counter, all inside the existing mkdir lock with its
# symlink/TOCTOU guards intact. The local counter is a CACHE, not an authority.
#
# Functions exported:
#   aif_id_kind_counter <kind>   -> prints the ~/.claude counter path for the kind
#   aif_id_kind_lockdir <kind>   -> prints the mkdir-lock dir path for the kind
#   aif_id_kind_prefix  <kind>   -> prints the id prefix (REQ|BUG|LESSON)
#   aif_id_kind_scan    <kind>   -> prints "<find-path-glob> <find-type>" for bootstrap
#   aif_id_list_max     <list>   -> max of a newline-separated number list (zsh-safe)
#   aif_remote_artifact_nums <repo> <kind> <prefix>  -> prints "<nums>\n<ran>" where
#                                   <ran>=1 iff a forge-aware artifact scan actually ran
#   aif_remote_high     <kind>   -> prints "<high_water> <degraded>" (BR-2)
#   aif_alloc_id        <kind>   -> prints max(local,remote)+1; fast-forwards the counter
#
# Degradation signalling (REQ-523 BR-2): aif_remote_high prints TWO space-separated
# tokens on stdout — "<high_water> <degraded>" — because both callers invoke it through
# command substitution ($(...)), a subshell whose variable writes can NEVER reach the
# parent (LESSON-015). The old "sets AIF_ALLOC_DEGRADED=1 in the CALLER's env" contract
# was structurally broken (the write died with the subshell); it is removed. The degraded
# bit is 1 whenever ANY source that should have run for the requested kind could not run
# or failed: ls-remote failure, gh absent AND git-transport fallback failed, gh api
# failure with no fallback, an Azure DevOps scan that could not run, a non-GitHub/non-ADO
# forge with no usable scan, or no participating remote at all. A warning is also emitted
# to stderr. The branch scan and the artifact scan are INDEPENDENT derivation sources
# (BR-1): a failure of one never skips the other for the same repo. For kind=lesson
# (branch-less), the artifact scan is the ONLY source, so its absence is ALWAYS degraded
# with a warning — never a silent 0 (BR-3). Allocation NEVER blocks on network
# availability — a degraded derivation still allocates from local state.
#
# Portable across sh/bash/zsh (BR-6): prefixed globals (no `local`), no `\b` in grep -E,
# no bare $<digit>, no [0] indexing, no `status=` variable, and NO `for x in $var`
# iteration over newline-separated lists — zsh does not word-split unquoted parameter
# expansions (SH_WORD_SPLIT off by default), so the whole list arrives as one word
# (BUG-116). Reduce lists via printf '%s\n' pipelines instead (LESSON-329). Modeled on
# trial-merge.sh.
#
# Prefix-sibling safety (REQ-524 audit): every id match in this file is either a
# maximal-munch EXTRACTION (`grep -oE '<PREFIX>-[0-9][0-9]*'` — ERE `*` is greedy, so
# scanning for REQ-120 against `REQ-1200-slug` extracts the full `1200`, never a
# truncated `120`) reduced by numeric max, or an exact-equality compare on the
# extracted number (`grep -qx` in id-recheck.sh). There is NO substring/`grep <id>`
# membership test keyed on a bare id, so REQ-120 vs REQ-1200 cannot cross-match
# (cf. renumber.py's _id_boundary_re/_id_boundary_ere; LESSON-016 substring buckets).

# --- numeric normalizer -------------------------------------------------------------
# Strip leading zeros so a value is treated as DECIMAL, not octal: in sh/bash/zsh
# `$(( 042 ))` is 34 (octal). Portable across all three (no `10#` bashism). Keeps a
# lone 0 as 0; empty input -> 0.
aif_id_dec() {
  printf '%s' "${1:-0}" | sed -E 's/^0+([0-9])/\1/' | sed -E 's/^$/0/'
}

# --- newline-safe list max ------------------------------------------------------------
# Max of a newline-separated number list, portable to zsh: never `for x in $var`
# (BUG-116 — zsh passes the whole list as one word and the integer test explodes).
# Each line is decimal-normalized (octal trap) before the sort. Empty input -> 0.
# A non-numeric line fails LOUD (ERROR on stderr, prints nothing, rc 2) instead of
# spamming per-candidate `[: integer expression expected` and degrading silently.
aif_id_list_max() {
  aif_lm_in=$(printf '%s\n' "${1:-}" | sed -E '/^[[:space:]]*$/d')
  if [ -z "$aif_lm_in" ]; then echo 0; return 0; fi
  if printf '%s\n' "$aif_lm_in" | grep -qvE '^[0-9]+$'; then
    echo "ERROR: aif_id_list_max: non-numeric candidate in id list — refusing integer compare (BUG-116)" >&2
    return 2
  fi
  printf '%s\n' "$aif_lm_in" | sed -E 's/^0+([0-9])/\1/' | sort -n | tail -1
}

# --- kind mappers (one table; three kinds; BR-8 one namespace per kind) -------------

aif_id_kind_prefix() {
  case "$1" in
    req)    echo "REQ" ;;
    bug)    echo "BUG" ;;
    lesson) echo "LESSON" ;;
    *) echo "aif_id_kind_prefix: unknown kind '$1' (want req|bug|lesson)" >&2; return 2 ;;
  esac
}

aif_id_kind_counter() {
  case "$1" in
    req)    echo "$HOME/.claude/.global-next-req" ;;
    bug)    echo "$HOME/.claude/.global-next-bug" ;;
    lesson) echo "$HOME/.claude/.global-next-lesson" ;;
    *) echo "aif_id_kind_counter: unknown kind '$1'" >&2; return 2 ;;
  esac
}

aif_id_kind_lockdir() {
  case "$1" in
    req)    echo "$HOME/.claude/.global-next-req.lock.d" ;;
    bug)    echo "$HOME/.claude/.global-next-bug.lock.d" ;;
    lesson) echo "$HOME/.claude/.global-next-lesson.lock.d" ;;
    *) echo "aif_id_kind_lockdir: unknown kind '$1'" >&2; return 2 ;;
  esac
}

# Prints "<find -path glob> <find -type flag>" for the bootstrap scan. REQ specs are
# directories (-type d); bugs and lessons are .md files (-type f) — deliberate, do not
# "correct" (see /bugfix SKILL.md note).
aif_id_kind_scan() {
  case "$1" in
    req)    echo "*/.aif/specs/REQ-* d" ;;
    bug)    echo "*/.aif/bugs/BUG-* f" ;;
    lesson) echo "*/.aif/knowledge/lessons/LESSON-* f" ;;
    *) echo "aif_id_kind_scan: unknown kind '$1'" >&2; return 2 ;;
  esac
}

# --- forge-aware artifact-path mapper -----------------------------------------------
# Prints the in-repo path that holds the merged artifacts for a kind.
aif_id_kind_artifact_path() {
  case "$1" in
    req)    echo ".aif/specs" ;;
    bug)    echo ".aif/bugs" ;;
    lesson) echo ".aif/knowledge/lessons" ;;
    *) echo "aif_id_kind_artifact_path: unknown kind '$1'" >&2; return 2 ;;
  esac
}

# --- forge host classifier (REQ-523 M4/BR-5) ----------------------------------------
# Classify an origin URL into a forge family, mirroring forge.sh aif_forge_provider's
# host-detection shape so the artifact scan resolves the SAME way the real PR ops do
# (LESSON-392). Prints: github | azure-devops | other.
aif_forge_host_class() {
  case "$1" in
    *github.com[:/]*)                                  echo "github" ;;
    *dev.azure.com[:/]*|*.visualstudio.com[:/]*|*.visualstudio.com:*) echo "azure-devops" ;;
    *)                                                 echo "other" ;;
  esac
}

# --- git-transport merged-artifact scan (REQ-523 BR-4/BR-5) -------------------------
# Forge-AGNOSTIC merged-artifact listing read straight from the REMOTE's default branch
# over git transport alone — works for gh-absent GitHub AND Azure DevOps (both speak
# git), never touching the local working tree. Resolve the default-branch tip via
# ls-remote, shallow-fetch that exact object if it is not already local (a stale clone
# may lack the newest tip), then ls-tree the artifact directory. Prints the artifact
# numbers (may be empty); rc 0 iff the scan actually ran (ls-tree succeeded), rc 1 if it
# could not run (transport failure). Never prints non-numeric noise.
aif_remote_git_artifact_nums() {
  aif_ga_repo=$1; aif_ga_kind=$2; aif_ga_prefix=$3
  aif_ga_path=$(aif_id_kind_artifact_path "$aif_ga_kind") || return 1
  aif_ga_tip=$(git -C "$aif_ga_repo" ls-remote origin HEAD 2>/dev/null | awk '{print $1; exit}')
  [ -n "$aif_ga_tip" ] || return 1
  # ls-tree fails if the tip object isn't local yet; shallow-fetch it and retry once.
  aif_ga_tree=$(git -C "$aif_ga_repo" ls-tree --name-only "$aif_ga_tip" "$aif_ga_path/" 2>/dev/null)
  if [ $? -ne 0 ]; then
    git -C "$aif_ga_repo" fetch --depth=1 -q origin "$aif_ga_tip" 2>/dev/null || return 1
    aif_ga_tree=$(git -C "$aif_ga_repo" ls-tree --name-only "$aif_ga_tip" "$aif_ga_path/" 2>/dev/null) || return 1
  fi
  printf '%s\n' "$aif_ga_tree" \
    | grep -oE "$aif_ga_prefix-[0-9][0-9]*" \
    | grep -oE '[0-9][0-9]*'
  return 0
}

# --- shared forge-aware artifact scan (REQ-523 BR-4/BR-5/BR-6) -----------------------
# The SINGLE artifact-derivation surface used by BOTH aif_remote_high and
# aif_recheck_id (BR-6 — no recheck-only copy). For a repo + kind, derive the merged
# artifact id numbers and report whether a scan actually ran.
# Prints two lines:
#   line 1: the newline-joined artifact numbers, joined by spaces (may be empty)
#   line 2: "1" if a scan ran (result is authoritative), "0" if no scan could run
# GitHub: try the cheap `gh api contents` read first; on gh-absent OR gh failure, fall
# through to the forge-agnostic git-transport scan. Azure DevOps + any other git host:
# the git-transport scan directly (BR-5 parity). The only "no scan ran" outcomes are an
# unrecognized host with no usable scan, or git-transport failure with no gh path.
aif_remote_artifact_nums() {
  aif_an_repo=$1; aif_an_kind=$2; aif_an_prefix=$3
  aif_an_url=$(git -C "$aif_an_repo" remote get-url origin 2>/dev/null)
  aif_an_host=$(aif_forge_host_class "$aif_an_url")
  aif_an_nums=""
  aif_an_ran=0

  if [ "$aif_an_host" = "github" ]; then
    # Fast path: gh api contents on owner/repo parsed from the URL.
    aif_an_owner=$(printf '%s' "$aif_an_url" \
      | sed -E 's#^git@github.com:##; s#^https://github.com/##; s#\.git$##')
    if command -v gh >/dev/null 2>&1 && printf '%s' "$aif_an_owner" | grep -qE '^[^/]+/[^/]+$'; then
      aif_an_apath=$(aif_id_kind_artifact_path "$aif_an_kind") || return 1
      aif_an_listing=$(gh api "repos/$aif_an_owner/contents/$aif_an_apath" --jq '.[].name' 2>/dev/null)
      if [ $? -eq 0 ] && [ -n "$aif_an_listing" ]; then
        aif_an_nums=$(printf '%s\n' "$aif_an_listing" \
          | grep -oE "$aif_an_prefix-[0-9][0-9]*" | grep -oE '[0-9][0-9]*')
        aif_an_ran=1
      fi
    fi
    # gh absent / gh failed / empty listing -> git-transport fallback (BR-4).
    if [ "$aif_an_ran" -eq 0 ]; then
      aif_an_nums=$(aif_remote_git_artifact_nums "$aif_an_repo" "$aif_an_kind" "$aif_an_prefix")
      [ $? -eq 0 ] && aif_an_ran=1
    fi
  elif [ "$aif_an_host" = "azure-devops" ]; then
    # ADO parity (BR-5): git transport speaks to ADO too. Full scan, not degraded.
    aif_an_nums=$(aif_remote_git_artifact_nums "$aif_an_repo" "$aif_an_kind" "$aif_an_prefix")
    [ $? -eq 0 ] && aif_an_ran=1
  else
    # Unrecognized host: try a generic git-transport scan (it may still be a git
    # remote); if even that fails, the scan did not run (caller flags degraded).
    aif_an_nums=$(aif_remote_git_artifact_nums "$aif_an_repo" "$aif_an_kind" "$aif_an_prefix")
    [ $? -eq 0 ] && aif_an_ran=1
  fi

  # Collapse the numbers to a single space-joined line so the two-line contract holds
  # even when the list is multi-element (BUG-116 — never word-split downstream).
  printf '%s\n%s\n' "$(printf '%s\n' "$aif_an_nums" | tr '\n' ' ' | sed -E 's/[[:space:]]+$//')" "$aif_an_ran"
}

# --- remote high-water derivation (REQ-523 BR-1/BR-2/BR-3/BR-4/BR-5) -----------------
# Reads the REMOTE, not local clones' state — stale local checkouts must not LOWER the
# result. Derive-don't-store surface (ADR-2): pushed feat/REQ-* / fix/bug-* branch names
# (req/bug) PLUS merged artifact dirs/files on the default branch, across participating
# repos = checkouts under $AIF_REPOS_ROOT (default: parent of the current repo) that
# have a remote.
#
# The branch scan and the artifact scan are INDEPENDENT sources (BR-1): a failed
# ls-remote no longer skips the artifact scan for the same repo. Prints
# "<high_water> <degraded>" on stdout (BR-2): the degraded bit (1/0) survives command
# substitution, unlike the old parent-env AIF_ALLOC_DEGRADED write. For kind=lesson the
# artifact scan is the ONLY source, so a repo where it could not run is ALWAYS degraded
# (BR-3).
aif_remote_high() {
  aif_rh_kind=$1
  aif_rh_prefix=$(aif_id_kind_prefix "$aif_rh_kind") || return 2

  # Branch pattern per kind: REQ -> feat/REQ-NNN-, BUG -> fix/bug-NNN- (lesson has no
  # branch of its own; it rides a feat/fix branch, so its remote footprint is the
  # merged lessons dir, scanned below).
  case "$aif_rh_kind" in
    req)    aif_rh_branch_re='feat/REQ-[0-9][0-9]*' ;;
    bug)    aif_rh_branch_re='fix/bug-[0-9][0-9]*' ;;
    lesson) aif_rh_branch_re='' ;;
  esac

  aif_rh_root="${AIF_REPOS_ROOT:-$(cd "$(git rev-parse --show-toplevel 2>/dev/null)/.." 2>/dev/null && pwd)}"
  [ -n "$aif_rh_root" ] || aif_rh_root="."

  aif_rh_max=0
  aif_rh_saw_remote=0
  aif_rh_degraded=0
  aif_rh_unreachable=""

  # Enumerate participating repos: git checkouts directly under the root that have an
  # `origin` remote. One level deep is the common "all repos under one folder" layout.
  # zsh aborts the whole enclosing eval on a no-match glob (NOMATCH); sh/bash leave the
  # pattern literal and the .git check skips it. Make zsh behave like nullglob, scoped
  # to this function (BUG-116 — an empty root must degrade loudly, not abort silently).
  if [ -n "${ZSH_VERSION:-}" ]; then setopt localoptions nullglob 2>/dev/null; fi
  for aif_rh_repo in "$aif_rh_root"/*; do
    [ -d "$aif_rh_repo/.git" ] || [ -f "$aif_rh_repo/.git" ] || continue
    aif_rh_url=$(git -C "$aif_rh_repo" remote get-url origin 2>/dev/null) || continue
    [ -n "$aif_rh_url" ] || continue
    aif_rh_saw_remote=1

    # --- SOURCE 1: pushed branch names (req/bug) via ls-remote on the REMOTE ---------
    # A failure here is recorded as degraded but does NOT skip SOURCE 2 (BR-1 — the two
    # sources are independent; git transport (SSH) and gh (HTTPS+token) fail apart).
    if [ -n "$aif_rh_branch_re" ]; then
      aif_rh_refs=$(git -C "$aif_rh_repo" ls-remote --heads origin 2>/dev/null)
      if [ $? -ne 0 ]; then
        aif_rh_unreachable="$aif_rh_unreachable $aif_rh_url"
        aif_rh_degraded=1
        # fall through — do NOT continue (BR-1).
      else
        # Extract NNN from refs/heads/<branch_re>-...; grep -oE then strip the prefix.
        # Reduce via aif_id_list_max — NOT `for x in $nums` (zsh word-split, BUG-116).
        aif_rh_nums=$(printf '%s\n' "$aif_rh_refs" \
          | grep -oE "$aif_rh_branch_re" \
          | grep -oE '[0-9][0-9]*' )
        aif_rh_cand=$(aif_id_list_max "$aif_rh_nums") || return 2
        [ "$aif_rh_cand" -gt "$aif_rh_max" ] && aif_rh_max=$aif_rh_cand
      fi
    fi

    # --- SOURCE 2: merged artifact dirs/files via the shared forge-aware scan --------
    # gh fast-path -> git-transport fallback (BR-4) -> ADO parity (BR-5). The helper
    # reports whether a scan actually ran; if not, this repo is degraded for the
    # requested kind. For lessons this is the ONLY source (BR-3).
    aif_rh_art=$(aif_remote_artifact_nums "$aif_rh_repo" "$aif_rh_kind" "$aif_rh_prefix")
    # Line 1 = space-joined artifact numbers; line 2 = scan-ran bit. Re-split the
    # numbers onto newlines for aif_id_list_max (which rejects a space-joined line).
    aif_rh_art_nums=$(printf '%s\n' "$aif_rh_art" | sed -n '1p' | tr ' ' '\n')
    aif_rh_art_ran=$(printf '%s\n' "$aif_rh_art" | sed -n '2p')
    if [ "$aif_rh_art_ran" = "1" ]; then
      aif_rh_cand=$(aif_id_list_max "$aif_rh_art_nums") || return 2
      [ "$aif_rh_cand" -gt "$aif_rh_max" ] && aif_rh_max=$aif_rh_cand
    else
      aif_rh_host=$(aif_forge_host_class "$aif_rh_url")
      echo "WARNING: merged-artifact scan could not run for $aif_rh_prefix in '$aif_rh_repo' (forge=$aif_rh_host, url=$aif_rh_url) — derivation degraded (BR-5)." >&2
      aif_rh_degraded=1
    fi
  done

  if [ -n "$aif_rh_unreachable" ]; then
    echo "WARNING: remote(s) unreachable during $aif_rh_prefix branch high-water derivation:$aif_rh_unreachable" >&2
    echo "  -> id allocated without full remote verification — verify before PR (BR-2)." >&2
  fi
  if [ "$aif_rh_saw_remote" -eq 0 ]; then
    echo "WARNING: no participating repo with an origin remote found under '$aif_rh_root' — local-only allocation (BR-3)." >&2
    aif_rh_degraded=1
  fi

  printf '%s %s\n' "$aif_rh_max" "$aif_rh_degraded"
}

# --- bootstrap scan (counter absent) ------------------------------------------------
# Local-filesystem high-water across $AIF_REPOS_ROOT — same as today's inline blocks.
# Only used to SEED an absent counter; remote derivation still runs on top.
aif_local_scan_high() {
  aif_ls_kind=$1
  aif_ls_prefix=$(aif_id_kind_prefix "$aif_ls_kind") || return 2
  aif_ls_scan=$(aif_id_kind_scan "$aif_ls_kind") || return 2
  # split "<glob> <type>"
  aif_ls_glob=${aif_ls_scan% *}
  aif_ls_type=${aif_ls_scan##* }
  aif_ls_root="${AIF_REPOS_ROOT:-$(cd "$(git rev-parse --show-toplevel 2>/dev/null)/.." 2>/dev/null && pwd)}"
  [ -n "$aif_ls_root" ] || aif_ls_root="."
  aif_ls_high=$(find "$aif_ls_root" -path "$aif_ls_glob" -type "$aif_ls_type" 2>/dev/null \
    | grep -oE "$aif_ls_prefix-[0-9]+" | sed "s/$aif_ls_prefix-//" | sort -n | tail -1)
  # Normalize to decimal — `$(( 042 + 1 ))` is 35 in sh/bash because a leading 0 means
  # octal (aif_id_dec strips leading zeros portably).
  aif_id_dec "${aif_ls_high:-0}"
}

# --- the allocator (BR-1) -----------------------------------------------------------
# Prints the allocated NUMBER (not the prefixed id) on stdout. The lock block is ported
# VERBATIM from /spec Step 2 (REQ-416 verify rationale comments preserved — LESSON-023),
# extended only with the remote high-water max.
aif_alloc_id() {
  aif_ai_kind=$1
  aif_ai_counter=$(aif_id_kind_counter "$aif_ai_kind") || return 2
  aif_ai_lock=$(aif_id_kind_lockdir "$aif_ai_kind") || return 2

  # Remote high-water is derived OUTSIDE the lock — it makes network calls that must
  # not hold the mkdir lock for seconds; the lock only guards the local read/write.
  # aif_remote_high prints "<high_water> <degraded>" (REQ-523 BR-2). Split the two
  # tokens; the high-water drives allocation, the degraded bit is surfaced to the caller.
  aif_ai_rh=$(aif_remote_high "$aif_ai_kind")
  aif_ai_remote=${aif_ai_rh%% *}
  aif_ai_degraded=${aif_ai_rh##* }
  # Loud-fail guard (BUG-116): the high-water token is always a number on success (0 when
  # degraded — that path stays non-blocking per BR-2/BR-3). Empty or non-numeric means an
  # internal derivation error — abort rather than silently allocating from local alone.
  case "$aif_ai_remote" in
    ''|*[!0-9]*)
      echo "ERROR: aif_remote_high returned non-numeric high-water '$aif_ai_remote' for kind '$aif_ai_kind' — aborting allocation (BUG-116)" >&2
      return 1 ;;
  esac
  # On a degraded derivation, warn on stderr (the warning detail already came from
  # aif_remote_high; this is the allocation-level summary). We do NOT set a parent-env
  # flag here: aif_alloc_id is itself invoked via $(...) in the sanctioned usage, so any
  # variable write would die in the subshell — the SAME class of bug REQ-523 repairs
  # (LESSON-015). The degraded bit is carried by the stdout token already consumed; a
  # skill that needs it must read it from aif_remote_high directly, not from a flag.
  if [ "$aif_ai_degraded" = "1" ]; then
    echo "WARNING: $aif_ai_kind id derived from a DEGRADED remote scan — verify before PR (REQ-523 BR-2)." >&2
  fi

  aif_ai_num=$(
    LOCK="$aif_ai_lock"
    COUNTER="$aif_ai_counter"
    REMOTE_HIGH="$aif_ai_remote"
    KIND="$aif_ai_kind"
    if [ -L "$LOCK" ]; then
      echo "ERROR: $LOCK is a symlink — refusing (TOCTOU risk). Inspect manually." >&2
      exit 1
    fi
    for _ in $(seq 50); do mkdir "$LOCK" 2>/dev/null && break; sleep 0.1; done
    # Hard-fail if we never acquired the lock (50 retries × 0.1s = ~5s budget).
    # Without this guard, a contended lock would silently fall through to the
    # critical section unguarded — defeating mutual exclusion (REQ-416 verify C1).
    [ -d "$LOCK" ] || { echo "ERROR: failed to acquire $LOCK after 50 retries — aborting to avoid duplicate id" >&2; exit 1; }

    # Counter read inside lock. If the counter is ABSENT, bootstrap-seed it from the
    # local filesystem scan (same as today). If it exists but is unreadable/empty mid
    # critical-section, fail hard rather than silently resetting the global counter
    # (REQ-416 verify M2).
    if [ -f "$COUNTER" ]; then
      NUM=$(cat "$COUNTER" 2>/dev/null) || { echo "ERROR: counter $COUNTER unreadable inside lock — aborting" >&2; rmdir "$LOCK" 2>/dev/null; exit 1; }
      [ -n "$NUM" ] || { echo "ERROR: counter $COUNTER is empty — aborting (would reset to 1)" >&2; rmdir "$LOCK" 2>/dev/null; exit 1; }
    else
      NUM=$(( $(aif_local_scan_high "$KIND") + 1 ))
    fi

    # The collision-safe step (BR-1): the local counter is a cache. Take the max of the
    # remotely-derived high-water and the local counter value, then allocate max+1.
    # Normalize both to decimal first (octal trap on any stray leading zero).
    NUM=$(aif_id_dec "$NUM")
    REMOTE_HIGH=$(aif_id_dec "$REMOTE_HIGH")
    LOCAL_HIGH=$(( NUM - 1 ))
    HIGH=$LOCAL_HIGH
    [ "$REMOTE_HIGH" -gt "$HIGH" ] && HIGH=$REMOTE_HIGH
    ALLOC=$(( HIGH + 1 ))

    # Fast-forward the local counter to one past the allocated id.
    echo $(( ALLOC + 1 )) > "$COUNTER"

    # rmdir is guarded by the same symlink check (residual TOCTOU window between
    # check and rmdir is accepted risk per ADR-4 — see LESSON-014).
    if [ ! -L "$LOCK" ]; then rmdir "$LOCK" 2>/dev/null; fi
    echo "$ALLOC"
  )
  # `exit 1` inside the $(...) subshell terminates only the subshell — aif_ai_num
  # would be silently empty. The CALLER must also guard (see header usage example).
  [ -n "$aif_ai_num" ] || { echo "ERROR: failed to allocate $aif_ai_kind number" >&2; return 1; }
  echo "$aif_ai_num"
}
