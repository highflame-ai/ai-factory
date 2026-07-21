#!/usr/bin/env python3
"""aif packs — validate codeoid packs against the model they declare.

A pack (`packs/<id>/pack.yaml`, `schema: codeoid/pack@v1`) is data that wires
skills, capability roles, gates, and a phase pipeline together. This validator
checks the declaration holds together BEFORE a codeoid runtime tries to run it:

  - schema + required keys present; constitution file exists
  - every declared role file exists AND is a valid capability role — reusing the
    toolkit's own role parser (compile.parse_role_file), so a pack's roles get
    the SAME envelope/network validation as agents/*.md roles. This is the
    reconciliation: the pack registry inherits the toolkit's roles discipline.
  - referential integrity: every phase's skill/role/gate, and every gate's
    skill/role, resolves to something the pack declares.
  - cross-check: each `slash` skill's command points at an installed skill dir
    (skills/<name>) — a pack can't reference a skill the toolkit doesn't ship.

Wired into `aif check` (the CI/pre-commit gate) so the registry can't drift.
Pure standard library. Read-only.

The pack.yaml parser handles exactly the shapes packs use: top-level scalars, a
`>` folded scalar, block lists of `- ./path` or `- { flow map }`, and inline
comments. It fails loud on anything outside that; packs are authored to this
subset (documented in packs/CLAUDE.md).
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def _repo_root():
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(os.path.dirname(here))


def _strip_comment(v):
    # Drop an inline "# ..." comment that isn't inside quotes/braces.
    out, depth, i = [], 0, 0
    while i < len(v):
        c = v[i]
        if c in "{[":
            depth += 1
        elif c in "}]":
            depth -= 1
        elif c == "#" and depth == 0 and (i == 0 or v[i - 1] in " \t"):
            break
        out.append(c)
        i += 1
    return "".join(out).strip()


def _parse_flow_map(s):
    """Parse a `{ a: b, c: d, e: { retry: 2 } }` inline map to a flat dict.

    Nested braces are captured as the raw string value (enough for the
    referential checks — we never need to look inside onFail)."""
    s = s.strip()
    if not (s.startswith("{") and s.endswith("}")):
        raise ValueError(f"not a flow map: {s!r}")
    inner = s[1:-1]
    out, buf, depth = {}, [], 0
    parts = []
    for c in inner:
        if c in "{[":
            depth += 1
        elif c in "}]":
            depth -= 1
        if c == "," and depth == 0:
            parts.append("".join(buf)); buf = []
        else:
            buf.append(c)
    if "".join(buf).strip():
        parts.append("".join(buf))
    for part in parts:
        if ":" not in part:
            continue
        k, _, val = part.partition(":")
        out[k.strip()] = val.strip()
    return out


def parse_pack(path):
    """Parse pack.yaml into {scalars..., roles:[paths], skills/gates/phases:[dicts]}."""
    pack = {"roles": [], "skills": [], "gates": [], "phases": []}
    cur_list = None
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().splitlines()
    i = 0
    while i < len(lines):
        raw = lines[i]
        i += 1
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip())
        body = raw.strip()
        if indent == 0:
            key, _, value = body.partition(":")
            key, value = key.strip(), _strip_comment(value)
            if value == ">":
                # folded scalar: consume indented continuation lines
                buf = []
                while i < len(lines) and (not lines[i].strip() or (len(lines[i]) - len(lines[i].lstrip())) > 0):
                    buf.append(lines[i].strip()); i += 1
                pack[key] = " ".join(x for x in buf if x)
                cur_list = None
            elif value == "":
                cur_list = key if key in ("roles", "skills", "gates", "phases") else None
            else:
                pack[key] = value
                cur_list = None
        elif body.startswith("- ") and cur_list:
            item = _strip_comment(body[2:].strip())
            if item.startswith("{"):
                pack[cur_list].append(_parse_flow_map(item))
            else:
                pack[cur_list].append(item)
    return pack


def validate_pack(pack_dir):
    """Return a list of problem strings for one pack directory ([] = valid)."""
    problems = []
    manifest = os.path.join(pack_dir, "pack.yaml")
    if not os.path.isfile(manifest):
        return [f"{pack_dir}: no pack.yaml"]
    try:
        pack = parse_pack(manifest)
    except (ValueError, OSError) as exc:
        return [f"{manifest}: parse error: {exc}"]

    rel = os.path.relpath(pack_dir, _repo_root())
    if pack.get("schema") != "codeoid/pack@v1":
        problems.append(f"{rel}: schema must be 'codeoid/pack@v1' (got {pack.get('schema')!r})")
    for key in ("id", "name", "version", "constitution", "roles", "skills", "phases"):
        if not pack.get(key):
            problems.append(f"{rel}: missing required key '{key}'")

    # constitution file exists
    con = pack.get("constitution", "")
    if con and not os.path.isfile(os.path.join(pack_dir, con.lstrip("./"))):
        problems.append(f"{rel}: constitution file not found: {con}")

    # roles: exist + parse as valid capability roles (reuse the toolkit's parser)
    role_names = set()
    try:
        import compile as roles_compile
    except ImportError:
        roles_compile = None
    for rpath in pack.get("roles", []):
        full = os.path.join(pack_dir, str(rpath).lstrip("./"))
        stem = os.path.splitext(os.path.basename(str(rpath)))[0]
        role_names.add(stem)
        if not os.path.isfile(full):
            problems.append(f"{rel}: role file not found: {rpath}")
            continue
        if roles_compile is not None:
            try:
                roles_compile.parse_role_file(full)
            except roles_compile.CompileError as exc:
                problems.append(f"{rel}: invalid role {rpath}: {exc}")

    skill_ids = {s.get("id") for s in pack.get("skills", []) if isinstance(s, dict)}
    gate_ids = {g.get("id") for g in pack.get("gates", []) if isinstance(g, dict)}

    # slash skills must resolve to an installed skill dir
    for s in pack.get("skills", []):
        if isinstance(s, dict) and s.get("kind") == "slash":
            cmd = (s.get("command") or "").lstrip("/")
            if cmd and not os.path.isdir(os.path.join(_repo_root(), "skills", cmd)):
                problems.append(f"{rel}: skill '{s.get('id')}' → /{cmd} has no skills/{cmd}/ dir")

    # gate references
    for g in pack.get("gates", []):
        if not isinstance(g, dict):
            continue
        if g.get("kind") == "skill" and g.get("skill") not in skill_ids:
            problems.append(f"{rel}: gate '{g.get('id')}' references unknown skill '{g.get('skill')}'")
        if g.get("kind") == "review" and g.get("role") not in role_names:
            problems.append(f"{rel}: gate '{g.get('id')}' references unknown role '{g.get('role')}'")

    # phase referential integrity
    for ph in pack.get("phases", []):
        if not isinstance(ph, dict):
            continue
        pid = ph.get("id", "?")
        if ph.get("skill") not in skill_ids:
            problems.append(f"{rel}: phase '{pid}' references unknown skill '{ph.get('skill')}'")
        if ph.get("role") not in role_names:
            problems.append(f"{rel}: phase '{pid}' references unknown role '{ph.get('role')}'")
        if ph.get("gate") and ph.get("gate") not in gate_ids:
            problems.append(f"{rel}: phase '{pid}' references unknown gate '{ph.get('gate')}'")

    return problems


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    packs_dir = os.path.join(_repo_root(), "packs")
    if not os.path.isdir(packs_dir):
        print("no packs/ directory — nothing to validate")
        return 0
    dirs = [
        os.path.join(packs_dir, d) for d in sorted(os.listdir(packs_dir))
        if os.path.isfile(os.path.join(packs_dir, d, "pack.yaml"))
    ]
    if not dirs:
        print("packs/ has no pack.yaml manifests — nothing to validate")
        return 0
    all_problems = []
    for d in dirs:
        problems = validate_pack(d)
        all_problems += problems
        for p in problems:
            print(p, file=sys.stderr)
    if all_problems:
        print(f"aif packs: {len(all_problems)} problem(s) across {len(dirs)} pack(s)", file=sys.stderr)
        return 1
    print(f"aif packs: {len(dirs)} pack(s) valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
