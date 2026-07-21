#!/usr/bin/env python3
"""perm_audit — classify Claude Code standing permission grants by risk.

Claude Code's "always allow" accumulates permission rules into
``.claude/settings.json`` and ``.claude/settings.local.json``. Over time that
allow-list drifts: a one-off ``Bash(curl … $TOKEN)`` or a broad ``Bash(*)``
becomes a permanent standing grant nobody revisits. This module reads those
files and classifies each ``permissions.allow`` rule:

  remove  — a standing grant that is a real risk: destructive commands,
            inline-credential / secret exposure, credential-store reads.
  review  — worth a human look: overly broad wildcards that grant far more
            than any single task needs.
  keep    — everything else (specific, bounded rules).
  exempt  — a remove/review-class rule the team deliberately kept, recorded in
            .claude/permissions-audit-exemptions.json ({"exempt": {rule: reason}});
            reported informationally, never fails the doctor check.

Shared by ``aif doctor``'s ``permissions-audit`` check (binary: FAIL iff any
``remove``-class grant exists) and the ``/audit-permissions`` skill (interactive
cleanup). One classifier, so the check and the skill can never disagree.

Pure standard library. Auditing only — this module NEVER edits a settings file;
removal is the human's decision (in the skill) or a manual edit.
"""

import json
import os
import re
import sys

# (compiled regex, risk class, why). Matched against the INNER command of a
# rule, e.g. the `...` in `Bash(...)`, and against the whole rule string.
_PATTERNS = [
    # --- remove: destructive standing grants -------------------------------
    # rm with a recursive flag in any spelling: -r, -rf, -fr, -f -r, --recursive
    (re.compile(r"\brm\s+(-[a-zA-Z]+\s+)*-[a-zA-Z]*r|\brm\b[^)|;&]*--recursive"), "remove",
     "recursive file deletion as a standing grant"),
    (re.compile(r"\b(DROP|TRUNCATE)\s+(TABLE|DATABASE|SCHEMA)\b", re.I), "remove",
     "destructive SQL as a standing grant"),
    (re.compile(r"git\s+push\s+.*(--force\b|\s-f\b|\s\+\S)"), "remove",
     "force-push (flag or +refspec) as a standing grant"),
    (re.compile(r"git\s+reset\s+--hard"), "remove",
     "hard reset as a standing grant"),
    # --- remove: credential / secret exposure ------------------------------
    # Env vars whose name IS or ENDS WITH a sensitive segment (underscore-
    # delimited, so $MONKEY / $KEYBOARD_LAYOUT don't match but $API_KEY,
    # $GITHUB_TOKEN, $DB_PASSWORD, $KEY, $SECRET do).
    (re.compile(r"\$\{?([A-Z0-9]+_)*(TOKEN|SECRET|PASSWORD|PASSWD|KEY|CREDS?|CREDENTIALS?)S?\b"),
     "remove", "command references a secret env var — standing grant can exfiltrate it"),
    (re.compile(r"(sk-[A-Za-z0-9]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16})"),
     "remove", "inline credential baked into a permission rule"),
    # --- remove: credential-store reads ------------------------------------
    # Specific stores only; .env excludes template flavors (.env.example etc.).
    (re.compile(r"(~|\$HOME)?/?\.(ssh|gnupg|kube|docker)/|\.aws/credentials|"
                r"/etc/shadow|security\s+find-generic-password|credentials\.json\b"), "remove",
     "reads a credential store / secrets file"),
    # .env is ambiguous by regex (cat .env reads secrets; cp .env.example .env
    # is setup) -> surface for a human, never auto-red. Template flavors excluded.
    (re.compile(r"\.env(?!\.(example|sample|template|dist|test)\b)\b"), "review",
     "touches a .env file — check whether this grant reads secrets"),
    # --- review: overly broad wildcards ------------------------------------
    (re.compile(r"^(Bash|Read|Write|Edit)\(\*\)$"), "review",
     "unbounded wildcard — grants far more than any single task needs"),
    (re.compile(r"^Bash\(:\*\)$|^Bash\(\*:\*\)$"), "review",
     "unbounded Bash wildcard"),
]

def classify_rule(rule):
    """Return (risk_class, why) for a permission rule string, or (None, '')."""
    if not isinstance(rule, str) or not rule:
        return None, ""
    # Inner command for Tool(cmd) rules, else the whole rule.
    m = re.match(r"^[A-Za-z]+\((.*)\)$", rule)
    inner = m.group(1) if m else rule
    for pat, klass, why in _PATTERNS:
        if pat.search(rule) or pat.search(inner):
            return klass, why
    return None, ""


def _load_allow(path):
    """Return ({rule: source_basename}, error_or_None) for permissions.allow."""
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except FileNotFoundError:
        return {}, None
    except (OSError, json.JSONDecodeError) as exc:
        return {}, f"{os.path.basename(path)} unreadable/unparseable ({exc.__class__.__name__})"
    allow = (data.get("permissions") or {}).get("allow") or []
    return {rule: os.path.basename(path) for rule in allow if isinstance(rule, str)}, None


def _load_exemptions(project_dir):
    """Deliberate keeps: .claude/permissions-audit-exemptions.json —
    {"exempt": {"<exact rule>": "<reason>"}}. Gives the /audit-permissions
    'keep' decision a durable home so a kept grant doesn't stay doctor-red."""
    path = os.path.join(project_dir, ".claude", "permissions-audit-exemptions.json")
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        return {k: str(v) for k, v in (data.get("exempt") or {}).items()}
    except (OSError, json.JSONDecodeError, AttributeError):
        return {}


def audit_dir(project_dir):
    """Classify allow rules across a project's settings + settings.local.

    Returns a list of dicts: {rule, source, class, why} for remove/review
    findings, plus review-class entries for unparseable settings files.
    Rules in both files carry both sources. Exempted rules (see
    _load_exemptions) are reported as class "exempt" — informational, never
    failing.
    """
    claude_dir = os.path.join(project_dir, ".claude")
    merged = {}
    findings = []
    for name in ("settings.json", "settings.local.json"):
        rules, err = _load_allow(os.path.join(claude_dir, name))
        if err:
            findings.append({"rule": "(file)", "source": name, "class": "review",
                             "why": f"could not audit: {err}"})
        for rule, source in rules.items():
            merged.setdefault(rule, []).append(source)
    exemptions = _load_exemptions(project_dir)
    for rule, sources in sorted(merged.items()):
        klass, why = classify_rule(rule)
        if not klass:
            continue
        source = ", ".join(sources)
        if rule in exemptions:
            findings.append({"rule": rule, "source": source, "class": "exempt",
                             "why": f"exempted: {exemptions[rule]}"})
        else:
            findings.append({"rule": rule, "source": source, "class": klass, "why": why})
    return findings


def has_settings(project_dir):
    claude_dir = os.path.join(project_dir, ".claude")
    return any(
        os.path.isfile(os.path.join(claude_dir, n))
        for n in ("settings.json", "settings.local.json")
    )


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    as_json = "--json" in argv
    project_dir = os.getcwd()
    if not has_settings(project_dir):
        msg = "no .claude/settings.json or settings.local.json in this directory"
        print(json.dumps({"findings": [], "note": msg}) if as_json else msg)
        return 0
    findings = audit_dir(project_dir)
    if as_json:
        print(json.dumps({"findings": findings}, indent=2))
    else:
        if not findings:
            print("permission audit: no risky standing grants found")
        for f in findings:
            print(f"[{f['class']}] {f['rule']}  ({f['source']}) — {f['why']}")
    return 1 if any(f["class"] == "remove" for f in findings) else 0


if __name__ == "__main__":
    raise SystemExit(main())
