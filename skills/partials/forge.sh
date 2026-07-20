# partials/forge.sh — forge-neutral PR-operation adapter (REQ-520).
#
# The SINGLE place gh/az PR commands live (BR-1). Source this partial, then call
# the adapter functions WITHIN THE SAME fenced block (conventions.md cross-fence
# rule):
#   . .aif/partials/forge.sh 2>/dev/null || . ~/.claude/skills/partials/forge.sh
#   out=$(aif_forge_pr_view "$pr" --fields state,url); rc=$?
#
# Provider resolution (BR-2): per-project .aif/config.yml forge.provider >
# machine ~/.claude/aif/config.yml forge.provider > auto (origin URL). `auto` on
# an unrecognized host fails loud (never a silent GitHub default). Resolution and
# the key-shaped-auth refusal live in tools/aif/forge_config.py (no shell YAML
# parsing — REQ-515 ADR-3); the no-config fast path stays pure-shell.
#
# Result/error surface (BR-4), normalized — identical field names from BOTH
# backends. On success: newline-delimited `key=value` lines. On failure:
#   error_class=<auth-missing|pr-not-found|merge-blocked-by-policy|feature-unsupported|network>
#   raw=<verbatim backend stderr>          # never swallowed (LESSON-008)
# and a non-zero return. Distinct failures never collapse into one label.
#
# State normalization (BR-4): pr_view.state in {OPEN, MERGED, CLOSED}. GitHub
# passes through; ADO active->OPEN, completed->MERGED, abandoned->CLOSED.
#
# Backends: github (gh), azure-devops (az repos). The GitHub path is BYTE-COMPATIBLE
# with the pre-migration direct `gh pr` calls (BR-3). AIF_FORGE_MOCK=1 routes every
# op to an offline fixture dispatcher (BR-10) — no gh/az/network.
#
# Credentials (BR-6): forge.auth is a source NAME (gh/az/an env-var name). PATs are
# read from the named env var at call time, NEVER echoed/logged/sent to telemetry.
#
# Portability (BR-9): prefixed globals (no `local`), no `set -eu` (return codes are
# the contract), no `\b` in grep -E, no bare $<digit>, no [0] indexing, no `status=`,
# no cross-block function state; $? captured immediately after each sub-call. Runs
# under sh/bash/zsh and Ubuntu bash.
#
# ADO REST-via-PAT fallback (documented, NOT shipped in v1 — ADR-2): when `az` is
# absent, each ADO op maps to a single ADO REST call authenticated by the PAT env
# var. The mapping per op:
#   pr_create -> POST  {org}/{proj}/_apis/git/repositories/{repo}/pullrequests?api-version=7.1
#   pr_view   -> GET   .../pullrequests/{id}?api-version=7.1
#   pr_list   -> GET   .../pullrequests?searchCriteria.status=active&api-version=7.1
#   pr_ready  -> PATCH .../pullrequests/{id}  body {"isDraft":false}
#   pr_edit   -> PATCH .../pullrequests/{id}  body {"title":...,"description":...}
#   pr_merge  -> PATCH .../pullrequests/{id}  body {"status":"completed",
#                "completionOptions":{"deleteSourceBranch":true,"mergeStrategy":"squash"}}
#   pr_comment-> POST  .../pullrequests/{id}/threads (thread API) — feature-unsupported in v1
# Auth header: `Authorization: Basic base64(:$PAT)`. A future REQ implements this
# behind the same adapter functions without changing any call site.

# --- internal: resolve provider into AIF_FORGE_PROVIDER --------------------
# Echoes the provider; exports AIF_FORGE_PROVIDER. rc!=0 on unrecognized auto.
# Honors the mock override (AIF_FORGE_MOCK_PROVIDER) so the offline matrix can
# exercise both providers without a real remote.
aif_forge_provider() {
  aif_fg_repo=${1:-.}
  if [ "${AIF_FORGE_MOCK:-0}" = "1" ]; then
    export AIF_FORGE_PROVIDER="${AIF_FORGE_MOCK_PROVIDER:-github}"
    printf '%s\n' "$AIF_FORGE_PROVIDER"
    return 0
  fi
  # Explicit override (callers/tests) short-circuits config + remote probes.
  if [ -n "${AIF_FORGE_PROVIDER_OVERRIDE:-}" ]; then
    export AIF_FORGE_PROVIDER="$AIF_FORGE_PROVIDER_OVERRIDE"
    printf '%s\n' "$AIF_FORGE_PROVIDER"
    return 0
  fi
  # Config file present anywhere in the precedence chain -> Python resolver
  # (handles project>machine>auto + fail-loud). Otherwise pure-shell auto.
  aif_fg_cfg_proj="$aif_fg_repo/.aif/config.yml"
  aif_fg_cfg_mach="${AIF_CONFIG:-${HOME:-}/.claude/aif/config.yml}"
  if [ -f "$aif_fg_cfg_proj" ] || [ -f "$aif_fg_cfg_mach" ]; then
    aif_fg_pv=$(_aif_forge_py "$aif_fg_repo" resolve-provider "$aif_fg_repo" 2>/dev/null)
    aif_fg_rc=$?
    if [ "$aif_fg_rc" -eq 0 ] && [ -n "$aif_fg_pv" ]; then
      export AIF_FORGE_PROVIDER="$aif_fg_pv"
      printf '%s\n' "$AIF_FORGE_PROVIDER"
      return 0
    fi
    if [ "$aif_fg_rc" -ne 0 ]; then
      # Resolver failed loud (unrecognized host / bad explicit provider). Surface it.
      _aif_forge_py "$aif_fg_repo" resolve-provider "$aif_fg_repo" >/dev/null
      return 2
    fi
  fi
  # No config: pure-shell auto from origin URL.
  aif_fg_url=$(git -C "$aif_fg_repo" remote get-url origin 2>/dev/null)
  case "$aif_fg_url" in
    *github.com[:/]*)  export AIF_FORGE_PROVIDER="github" ;;
    *dev.azure.com[:/]*|*.visualstudio.com[:/]*|*.visualstudio.com:*)
                       export AIF_FORGE_PROVIDER="azure-devops" ;;
    "") echo "forge: cannot auto-detect provider: no 'origin' remote. Set forge.provider in .aif/config.yml (github|azure-devops)." >&2
        return 2 ;;
    *)  echo "forge: cannot auto-detect provider from origin URL '$aif_fg_url'. Supported: github, azure-devops. Set forge.provider explicitly." >&2
        return 2 ;;
  esac
  printf '%s\n' "$AIF_FORGE_PROVIDER"
  return 0
}

# Locate and invoke forge_config.py with the two-level fallback (project vendored
# copy first, then toolkit). Args after the repo are passed to the script.
_aif_forge_py() {
  aif_fp_repo=$1
  shift
  aif_fp_local="$aif_fp_repo/tools/aif/forge_config.py"
  aif_fp_vend="$aif_fp_repo/.aif/tools/aif/forge_config.py"
  aif_fp_glob="${HOME:-}/.claude/skills/tools/aif/forge_config.py"
  # New layout: ~/.claude/skills targets <repo>/skills, so tools/ is its sibling.
  [ -f "$aif_fp_glob" ] || aif_fp_glob="${HOME:-}/.claude/skills/../tools/aif/forge_config.py"
  if [ -f "$aif_fp_local" ]; then
    python3 "$aif_fp_local" "$@"
  elif [ -f "$aif_fp_vend" ]; then
    python3 "$aif_fp_vend" "$@"
  else
    python3 "$aif_fp_glob" "$@"
  fi
}

# --- internal: normalized error emission ------------------------------------
# _aif_forge_err <class> <raw-stderr-file-or-string>
# Echoes the normalized class + verbatim raw stderr beneath it (BR-4).
_aif_forge_err() {
  aif_fe_class=$1
  aif_fe_raw=$2
  printf 'error_class=%s\n' "$aif_fe_class"
  if [ -f "$aif_fe_raw" ]; then
    while IFS= read -r aif_fe_line; do
      printf 'raw=%s\n' "$aif_fe_line"
    done < "$aif_fe_raw"
  elif [ -n "$aif_fe_raw" ]; then
    printf 'raw=%s\n' "$aif_fe_raw"
  fi
}

# Classify backend stderr into a normalized error class. Order matters: the most
# specific signatures first. Anything unmatched is `network` (the conservative
# default for "the call failed but we can't attribute it") — callers still get the
# raw stderr beneath it, so nothing is lost (BR-4).
_aif_forge_classify() {
  aif_fc_raw=$1
  case "$aif_fc_raw" in
    *"not logged"*|*"auth status"*|*"authentication"*|*"Unauthorized"*|*"TF400813"*|*"PAT"*"not set"*|*"auth-missing"*|*"az login"*|*"gh auth login"*|*"Please run"*"login"*|*"credentials"*)
      echo "auth-missing" ;;
    *"not found"*|*"Not Found"*|*"could not resolve"*|*"no pull request"*|*"TF401174"*)
      echo "pr-not-found" ;;
    *"policy"*|*"Policy"*|*"required review"*|*"branch protection"*|*"TF402455"*|*"not mergeable"*|*"blocked"*)
      echo "merge-blocked-by-policy" ;;
    *"unsupported"*|*"not supported"*|*"feature-unsupported"*)
      echo "feature-unsupported" ;;
    *)
      echo "network" ;;
  esac
}

# --- mock backend (BR-10) ---------------------------------------------------
# Deterministic offline fixtures keyed by (op, AIF_FORGE_MOCK_PROVIDER,
# AIF_FORGE_MOCK_SCENARIO). SCENARIO defaults to `ok`; set it to an error-class
# name to drive the failure path. Honors provider semantics faithfully:
# ADO pr_comment is feature-unsupported; state normalization differs by provider.
_aif_forge_mock() {
  aif_mk_op=$1
  aif_mk_prov="${AIF_FORGE_MOCK_PROVIDER:-github}"
  aif_mk_scn="${AIF_FORGE_MOCK_SCENARIO:-ok}"
  # ADO pr_comment is always feature-unsupported in v1, regardless of scenario.
  if [ "$aif_mk_op" = "pr_comment" ] && [ "$aif_mk_prov" = "azure-devops" ]; then
    _aif_forge_err "feature-unsupported" "ADO pr_comment is not supported in v1 (no az repos comment subcommand; REST thread API deferred)"
    return 1
  fi
  case "$aif_mk_scn" in
    ok) : ;;
    auth-missing|pr-not-found|merge-blocked-by-policy|feature-unsupported|network)
      _aif_forge_err "$aif_mk_scn" "mock backend ($aif_mk_prov): simulated $aif_mk_scn for $aif_mk_op"
      return 1 ;;
    *)
      _aif_forge_err "network" "mock backend: unknown scenario '$aif_mk_scn'"
      return 1 ;;
  esac
  # Happy-path normalized output per op. State normalization is provider-aware:
  # the mock returns already-normalized OPEN/MERGED/CLOSED (the adapter's job).
  case "$aif_mk_op" in
    pr_create) printf 'url=%s\nnumber=%s\nstate=OPEN\n' "https://mock.forge/$aif_mk_prov/pr/101" "101" ;;
    pr_ready)  printf 'state=OPEN\n' ;;
    pr_edit)   printf 'url=%s\n' "https://mock.forge/$aif_mk_prov/pr/101" ;;
    pr_view)   printf 'number=%s\nurl=%s\nstate=%s\nmergedAt=%s\nbody=%s\n' "101" "https://mock.forge/$aif_mk_prov/pr/101" "OPEN" "" "mock body" ;;
    pr_list)   printf 'number=101|url=https://mock.forge/%s/pr/101|head=feat/REQ-520-forge-adapter\n' "$aif_mk_prov" ;;
    pr_merge)  printf 'state=MERGED\n' ;;
    pr_comment) printf 'ok=1\n' ;;
    *) _aif_forge_err "network" "mock backend: unknown op '$aif_mk_op'"; return 1 ;;
  esac
  return 0
}

# --- backend runner: run a command, capture stderr, classify on failure ------
# _aif_forge_run -- <cmd...>
# A leading `--` sentinel separates the runner's own (currently none) options from
# the command argv; it is shifted off before exec. Runs the command; on success
# streams stdout; on failure classifies stderr and emits the normalized error
# block. Returns the command's rc (non-zero on failure).
_aif_forge_run() {
  [ "$1" = "--" ] && shift
  aif_rn_errf=$(mktemp 2>/dev/null || mktemp -t forge)
  # shellcheck disable=SC2068 — intentional: run the passed argv as the command.
  aif_rn_out=$("$@" 2>"$aif_rn_errf")
  aif_rn_rc=$?
  if [ "$aif_rn_rc" -eq 0 ]; then
    [ -n "$aif_rn_out" ] && printf '%s\n' "$aif_rn_out"
    rm -f "$aif_rn_errf"
    return 0
  fi
  aif_rn_rawall=$(cat "$aif_rn_errf" 2>/dev/null)
  aif_rn_class=$(_aif_forge_classify "$aif_rn_rawall")
  _aif_forge_err "$aif_rn_class" "$aif_rn_errf"
  rm -f "$aif_rn_errf"
  return "$aif_rn_rc"
}

# ============================================================================
# Public ops. Each resolves the provider (cheap, cached in AIF_FORGE_PROVIDER),
# then dispatches. The GitHub branch reproduces the exact pre-migration `gh`
# command/flags (BR-3). All ops honor AIF_FORGE_MOCK.
# ============================================================================

# aif_forge_pr_create --base B --head H --title T --body BODY [--draft]
aif_forge_pr_create() {
  [ "${AIF_FORGE_MOCK:-0}" = "1" ] && { _aif_forge_mock pr_create; return $?; }
  aif_forge_provider "${AIF_FORGE_REPO:-.}" >/dev/null || return 2
  case "$AIF_FORGE_PROVIDER" in
    github)
      # Byte-compatible with: gh pr create --base .. --head .. --title .. --body .. [--draft]
      # gh pr create prints the new PR URL on stdout. Normalize it to url=/state=.
      aif_fc_out=$(_aif_forge_run -- gh pr create "$@"); aif_fc_rc=$?
      [ "$aif_fc_rc" -ne 0 ] && { printf '%s\n' "$aif_fc_out"; return "$aif_fc_rc"; }
      # The runner already streamed the raw URL; re-emit as a normalized field too.
      printf 'url=%s\nstate=OPEN\n' "$aif_fc_out"; return 0 ;;
    azure-devops)
      _aif_forge_run -- az repos pr create "$@"; return $? ;;
    *) _aif_forge_err "feature-unsupported" "no backend for provider '$AIF_FORGE_PROVIDER'"; return 1 ;;
  esac
}

# aif_forge_pr_ready <number|url>
aif_forge_pr_ready() {
  [ "${AIF_FORGE_MOCK:-0}" = "1" ] && { _aif_forge_mock pr_ready; return $?; }
  aif_forge_provider "${AIF_FORGE_REPO:-.}" >/dev/null || return 2
  case "$AIF_FORGE_PROVIDER" in
    github)       _aif_forge_run -- gh pr ready "$@"; aif_fr_rc=$?; [ "$aif_fr_rc" -eq 0 ] && printf 'state=OPEN\n'; return "$aif_fr_rc" ;;
    azure-devops) _aif_forge_run -- az repos pr update --id "$@" --draft false; aif_fr_rc=$?; [ "$aif_fr_rc" -eq 0 ] && printf 'state=OPEN\n'; return "$aif_fr_rc" ;;
    *) _aif_forge_err "feature-unsupported" "no backend for provider '$AIF_FORGE_PROVIDER'"; return 1 ;;
  esac
}

# aif_forge_pr_edit <number|url> [--title T] [--body BODY] [--body-file F]
aif_forge_pr_edit() {
  [ "${AIF_FORGE_MOCK:-0}" = "1" ] && { _aif_forge_mock pr_edit; return $?; }
  aif_forge_provider "${AIF_FORGE_REPO:-.}" >/dev/null || return 2
  case "$AIF_FORGE_PROVIDER" in
    github)       _aif_forge_run -- gh pr edit "$@"; return $? ;;
    azure-devops)
      # gh's --title/--body map to az repos pr update --title/--description; caller
      # passes gh-shaped flags, the ADO call-site adapter translates. For v1 the
      # migrated call sites pass gh-shaped flags only through the github branch;
      # ADO edit goes through az with the id positional.
      _aif_forge_run -- az repos pr update --id "$@"; return $? ;;
    *) _aif_forge_err "feature-unsupported" "no backend for provider '$AIF_FORGE_PROVIDER'"; return 1 ;;
  esac
}

# aif_forge_pr_view <number|url> --fields f1,f2,...   (normalized mode)
#                    | <number|url> --json … [-q …] [-R …]   (raw passthrough)
#
# Two modes, by flag shape:
#   * --fields f1,f2,…  -> normalized: emits requested fields as key=value with
#     state coerced to {OPEN,MERGED,CLOSED} (the cross-backend contract).
#   * gh-native --json/-q/--jq/-R (no --fields) -> raw passthrough: the GitHub
#     backend forwards the WHOLE argv verbatim to `gh pr view`, so callers that
#     need the raw body string (e.g. footprint reads) stay byte-identical (BR-3).
#     ADO has no raw-gh shape; it always normalizes via `az repos pr show`.
aif_forge_pr_view() {
  [ "${AIF_FORGE_MOCK:-0}" = "1" ] && { _aif_forge_mock pr_view; return $?; }
  aif_fv_ref=""
  aif_fv_fields=""
  aif_fv_raw_mode=0
  for aif_fv_a in "$@"; do
    case "$aif_fv_a" in
      --json|-q|--jq|-R|--repo) aif_fv_raw_mode=1 ;;
    esac
  done
  # Locate --fields (normalized mode) and the ref positional without consuming
  # the gh-native flags (which raw mode forwards verbatim).
  aif_fv_prev=""
  for aif_fv_a in "$@"; do
    if [ "$aif_fv_prev" = "--fields" ]; then aif_fv_fields=$aif_fv_a; fi
    case "$aif_fv_a" in
      --*|-*) : ;;
      *) [ -z "$aif_fv_ref" ] && [ "$aif_fv_prev" != "--fields" ] && aif_fv_ref=$aif_fv_a ;;
    esac
    aif_fv_prev=$aif_fv_a
  done
  [ -n "$aif_fv_fields" ] && aif_fv_raw_mode=0
  [ -n "$aif_fv_fields" ] || aif_fv_fields="state,url,number"
  aif_forge_provider "${AIF_FORGE_REPO:-.}" >/dev/null || return 2
  case "$AIF_FORGE_PROVIDER" in
    github)
      if [ "$aif_fv_raw_mode" = "1" ]; then
        # Byte-compatible raw passthrough: exactly `gh pr view <args…>`.
        _aif_forge_run -- gh pr view "$@"; return $?
      fi
      aif_fv_raw=$(_aif_forge_run -- gh pr view "$aif_fv_ref" --json "$aif_fv_fields"); aif_fv_rc=$?
      [ "$aif_fv_rc" -ne 0 ] && { printf '%s\n' "$aif_fv_raw"; return "$aif_fv_rc"; }
      # GitHub states already match {OPEN,MERGED,CLOSED}; emit normalized k=v.
      printf '%s\n' "$aif_fv_raw" | _aif_forge_json_to_kv ;;
    azure-devops)
      aif_fv_raw=$(_aif_forge_run -- az repos pr show --id "$aif_fv_ref"); aif_fv_rc=$?
      [ "$aif_fv_rc" -ne 0 ] && { printf '%s\n' "$aif_fv_raw"; return "$aif_fv_rc"; }
      # ADO status active|completed|abandoned -> OPEN|MERGED|CLOSED (BR-4).
      printf '%s\n' "$aif_fv_raw" | _aif_forge_ado_view_to_kv ;;
    *) _aif_forge_err "feature-unsupported" "no backend for provider '$AIF_FORGE_PROVIDER'"; return 1 ;;
  esac
}

# aif_forge_pr_list --state open --branch-pattern PAT
aif_forge_pr_list() {
  [ "${AIF_FORGE_MOCK:-0}" = "1" ] && { _aif_forge_mock pr_list; return $?; }
  aif_forge_provider "${AIF_FORGE_REPO:-.}" >/dev/null || return 2
  case "$AIF_FORGE_PROVIDER" in
    github)       _aif_forge_run -- gh pr list "$@"; return $? ;;
    azure-devops) _aif_forge_run -- az repos pr list "$@"; return $? ;;
    *) _aif_forge_err "feature-unsupported" "no backend for provider '$AIF_FORGE_PROVIDER'"; return 1 ;;
  esac
}

# aif_forge_pr_merge <number|url> [--squash] [--delete-branch]
aif_forge_pr_merge() {
  [ "${AIF_FORGE_MOCK:-0}" = "1" ] && { _aif_forge_mock pr_merge; return $?; }
  aif_forge_provider "${AIF_FORGE_REPO:-.}" >/dev/null || return 2
  case "$AIF_FORGE_PROVIDER" in
    github)
      _aif_forge_run -- gh pr merge "$@"; aif_fm_rc=$?
      [ "$aif_fm_rc" -eq 0 ] && printf 'state=MERGED\n'; return "$aif_fm_rc" ;;
    azure-devops)
      # REQ-523 BR-9: callers pass gh-shaped flags (`<ref> --squash --delete-branch`).
      # `az repos pr update` does NOT understand `--squash` (bare) or `--delete-branch`;
      # forwarding "$@" verbatim made the ADO merge error out. Split the PR ref (first
      # non-flag positional) from the gh-shaped flags and TRANSLATE:
      #   --squash         -> --squash true
      #   --delete-branch  -> --delete-source-branch true
      # Other gh-only flags (e.g. --merge/--rebase/--admin) are dropped for v1; never
      # forwarded verbatim. --status completed is always set (auto-complete the PR).
      # Build the az flag list portably (no arrays — sh/bash/zsh parity): rebuild the
      # positional set so the ref and translated flags survive word boundaries safely.
      aif_fm_ref=""
      aif_fm_squash=""
      aif_fm_delsrc=""
      for aif_fm_a in "$@"; do
        case "$aif_fm_a" in
          --squash)        aif_fm_squash="--squash true" ;;
          --delete-branch) aif_fm_delsrc="--delete-source-branch true" ;;
          --merge|--rebase|--admin|--auto) : ;;  # gh-only; drop (never forward to az)
          --*) : ;;                               # any other gh-only flag; drop
          *) [ -z "$aif_fm_ref" ] && aif_fm_ref="$aif_fm_a" ;;  # first positional = ref
        esac
      done
      if [ -z "$aif_fm_ref" ]; then
        _aif_forge_err "pr-not-found" "aif_forge_pr_merge (azure-devops): no PR id/url positional in args: $*"
        return 1
      fi
      # Rebuild argv as: --id <ref> --status completed [--squash true] [--delete-source-branch true]
      # via `set --` so each translated token is a distinct word (no eval, no array).
      set -- --id "$aif_fm_ref" --status completed
      [ -n "$aif_fm_squash" ] && set -- "$@" --squash true
      [ -n "$aif_fm_delsrc" ] && set -- "$@" --delete-source-branch true
      # Policy blocks surface as merge-blocked-by-policy via the classifier (never
      # bypassed — ethos #6).
      _aif_forge_run -- az repos pr update "$@"; aif_fm_rc=$?
      [ "$aif_fm_rc" -eq 0 ] && printf 'state=MERGED\n'; return "$aif_fm_rc" ;;
    *) _aif_forge_err "feature-unsupported" "no backend for provider '$AIF_FORGE_PROVIDER'"; return 1 ;;
  esac
}

# aif_forge_pr_comment <number|url> --body BODY
aif_forge_pr_comment() {
  [ "${AIF_FORGE_MOCK:-0}" = "1" ] && { _aif_forge_mock pr_comment; return $?; }
  aif_forge_provider "${AIF_FORGE_REPO:-.}" >/dev/null || return 2
  case "$AIF_FORGE_PROVIDER" in
    github)       _aif_forge_run -- gh pr comment "$@"; aif_fcm_rc=$?; [ "$aif_fcm_rc" -eq 0 ] && printf 'ok=1\n'; return "$aif_fcm_rc" ;;
    azure-devops) _aif_forge_err "feature-unsupported" "ADO pr_comment is not supported in v1 (no az repos comment subcommand; REST thread API deferred)"; return 1 ;;
    *) _aif_forge_err "feature-unsupported" "no backend for provider '$AIF_FORGE_PROVIDER'"; return 1 ;;
  esac
}

# --- JSON -> key=value helpers (no jq dependency; gh emits compact JSON) -----
# GitHub: pass-through state. Minimal parser for the flat fields gh --json emits.
_aif_forge_json_to_kv() {
  python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if isinstance(d, dict):
    for k, v in d.items():
        if isinstance(v, (dict, list)):
            v = json.dumps(v, separators=(",", ":"))
        print(f"{k}={v}")
'
}

# ADO: normalize `status` -> state {OPEN,MERGED,CLOSED}; surface url/number/title.
_aif_forge_ado_view_to_kv() {
  python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if not isinstance(d, dict):
    sys.exit(0)
status = (d.get("status") or "").lower()
state = {"active": "OPEN", "completed": "MERGED", "abandoned": "CLOSED"}.get(status, status.upper())
print(f"state={state}")
num = d.get("pullRequestId")
if num is not None:
    print(f"number={num}")
url = d.get("url") or d.get("_links", {}).get("web", {}).get("href")
if url:
    print(f"url={url}")
ct = d.get("closedDate")
if status == "completed" and ct:
    print(f"mergedAt={ct}")
desc = d.get("description")
if desc is not None:
    print(f"body={desc}")
'
}
