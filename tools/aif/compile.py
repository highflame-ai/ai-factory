#!/usr/bin/env python3
"""aif compile — emit the roles/*.yaml capability model to every agent target.

``roles/*.yaml`` is the single source of truth for what each agent role MAY
do. One definition per role (envelope semantics: the role is the permission
BOUNDARY; each agent's frontmatter declares a subset), compiled to:

  claude   — validation of ``agents/*.md`` frontmatter: every agent's
             ``tools:`` must be a subset of its tier-role's envelope plus any
             declared exception. Claude is the native layer, so nothing is
             generated — drift is CHECKED, not stamped.
  codex    — ``compiled/codex/config.toml``: one profile per role mapping the
             capability envelope onto Codex approval/sandbox semantics.
  copilot  — ``compiled/copilot/copilot-instructions-roles.md``: a paste-in
             block for ``.github/copilot-instructions.md`` stating each
             role's boundary in prose (Copilot has no per-role enforcement
             surface; this is convention, and the block says so).
  cedar    — ``compiled/cedar/roles.cedarschema`` + ``roles.cedar``: entity
             schema + one policy set per role, for orgs that enforce agent
             capabilities at a gateway. Optional layer — emitted always,
             deployed only where an enforcement layer exists.

Deterministic output (no timestamps): ``--check`` re-generates in memory and
diffs against ``compiled/``, so CI can fail on drift. Pure standard library,
same as the rest of ``tools/aif`` — the YAML subset parser below handles
exactly the constrained shape the role files use (flat scalars, one string
list or the literal ``all``, a two-level ``exceptions:`` map with inline
``add: [..]`` lists). No anchors, no multiline strings, no nesting beyond
that — the parser fails loud on anything else.
"""

import json
import os
import re
import sys

# Canonical (lowercase) tool vocabulary. Claude tool names map onto these;
# mcp__<server>__* collapses to mcp:<server>.
_CANONICAL = ("read", "grep", "glob", "bash", "edit", "write", "monitor")
_WRITE_TOOLS = {"edit", "write"}

_CLAUDE_TO_CANONICAL = {
    "read": "read", "grep": "grep", "glob": "glob", "bash": "bash",
    "edit": "edit", "write": "write", "monitor": "monitor",
    "notebookedit": "edit",
}

_ROLE_ORDER = ("reviewer", "scanner", "explorer", "implementer", "orchestrator")

_NETWORK_LEVELS = ("false", "read-only", "true")


def _network_level(role):
    """Normalize the role's network flag to 'false' | 'read-only' | 'true'."""
    v = role.get("network", False)
    if v is True:
        return "true"
    if v is False:
        return "false"
    if v == "read-only":
        return "read-only"
    raise CompileError(
        f"role '{role.get('name', '?')}': network must be one of {', '.join(_NETWORK_LEVELS)}"
    )


class CompileError(Exception):
    pass


def _repo_root():
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(os.path.dirname(here))


# --------------------------------------------------------------------------
# Constrained YAML subset parser for roles/*.yaml
# --------------------------------------------------------------------------
def parse_role_file(path):
    role = {"envelope": [], "exceptions": {}}
    cur_list = None          # key currently collecting "- item" lines
    cur_exception = None     # agent name currently collecting exception keys
    with open(path, encoding="utf-8") as fh:
        for lineno, raw in enumerate(fh, 1):
            line = raw.rstrip("\n")
            stripped = line.split("#", 1)[0].rstrip() if not line.lstrip().startswith("#") else ""
            if not stripped.strip():
                continue
            indent = len(stripped) - len(stripped.lstrip())
            body = stripped.strip()

            if indent == 0:
                cur_exception = None
                key, _, value = body.partition(":")
                key, value = key.strip(), value.strip()
                if key == "envelope":
                    if value == "all":
                        role["envelope"] = "all"
                        cur_list = None
                    elif value == "":
                        cur_list = "envelope"
                    else:
                        raise CompileError(f"{path}:{lineno}: envelope must be 'all' or a list")
                elif key == "exceptions":
                    cur_list = None
                elif value == "":
                    raise CompileError(f"{path}:{lineno}: unexpected empty mapping '{key}'")
                else:
                    cur_list = None
                    if value in ("true", "false"):
                        role[key] = value == "true"
                    else:
                        role[key] = value
            elif body.startswith("- "):
                if cur_list != "envelope" or role["envelope"] == "all":
                    raise CompileError(f"{path}:{lineno}: stray list item")
                item = body[2:].strip()
                if item not in _CANONICAL:
                    raise CompileError(
                        f"{path}:{lineno}: unknown tool '{item}' "
                        f"(allowed: {', '.join(_CANONICAL)})"
                    )
                role["envelope"].append(item)
            elif indent == 2 and body.endswith(":"):
                cur_exception = body[:-1].strip()
                role["exceptions"][cur_exception] = {"add": [], "reason": ""}
            elif indent >= 4 and cur_exception:
                key, _, value = body.partition(":")
                key, value = key.strip(), value.strip()
                if key == "add":
                    m = re.match(r"^\[(.*)\]$", value)
                    if not m:
                        raise CompileError(f"{path}:{lineno}: add must be an inline list [a, b]")
                    items = [t.strip() for t in m.group(1).split(",") if t.strip()]
                    for t in items:
                        if t not in _CANONICAL:
                            raise CompileError(f"{path}:{lineno}: unknown tool '{t}'")
                    role["exceptions"][cur_exception]["add"] = items
                elif key == "reason":
                    role["exceptions"][cur_exception]["reason"] = value
                else:
                    raise CompileError(f"{path}:{lineno}: unknown exception key '{key}'")
            else:
                raise CompileError(f"{path}:{lineno}: unparseable line: {body!r}")
    for req in ("name", "summary"):
        if req not in role:
            raise CompileError(f"{path}: missing required key '{req}'")
    if "write" not in role:
        raise CompileError(f"{path}: missing required key 'write'")
    for agent, exc in role["exceptions"].items():
        if not exc["reason"]:
            raise CompileError(f"{path}: exception '{agent}' needs a reason")
    if "network" in role and role["network"] not in (True, False, "read-only"):
        raise CompileError(f"{path}: network must be true, false, or read-only")
    return role


def load_roles(root):
    rdir = os.path.join(root, "roles")
    if not os.path.isdir(rdir):
        raise CompileError(f"roles/ directory not found at {rdir}")
    roles = {}
    for fn in sorted(os.listdir(rdir)):
        if fn.endswith(".yaml"):
            role = parse_role_file(os.path.join(rdir, fn))
            roles[role["name"]] = role
    missing = [r for r in _ROLE_ORDER if r not in roles]
    if missing:
        raise CompileError(f"roles/ is missing definitions for: {', '.join(missing)}")
    return roles


# --------------------------------------------------------------------------
# Agent frontmatter reading
# --------------------------------------------------------------------------
def load_agents(root):
    """Return {agent_name: {"tier": str, "tools": [canonical...] | "all"}}."""
    adir = os.path.join(root, "agents")
    agents = {}
    for fn in sorted(os.listdir(adir)):
        if not fn.endswith(".md"):
            continue
        name = fn[:-3]
        tier, tools_line, has_tools = None, "", False
        with open(os.path.join(adir, fn), encoding="utf-8") as fh:
            in_fm = False
            for i, line in enumerate(fh):
                if line.strip() == "---":
                    if i == 0:
                        in_fm = True
                        continue
                    break
                if not in_fm:
                    break
                if line.startswith("tier:"):
                    tier = line.split(":", 1)[1].strip()
                if line.startswith("tools:"):
                    has_tools = True
                    tools_line = line.split(":", 1)[1].strip()
        if tier is None:
            raise CompileError(f"agents/{fn}: no tier: frontmatter")
        if not has_tools:
            tools = "all"     # no tools line = unrestricted (effort-class agents)
        else:
            tools = []
            for raw_tool in tools_line.split(","):
                t = raw_tool.strip()
                if not t:
                    continue
                m = re.match(r"^mcp__([a-z0-9-]+)__", t, re.IGNORECASE)
                if m:
                    canonical = "mcp:" + m.group(1).lower()
                elif t.lower() in _CLAUDE_TO_CANONICAL:
                    canonical = _CLAUDE_TO_CANONICAL[t.lower()]
                else:
                    raise CompileError(f"agents/{fn}: unmappable tool '{t}'")
                if canonical not in tools:
                    tools.append(canonical)
        agents[name] = {"tier": tier, "tools": tools}
    return agents


# --------------------------------------------------------------------------
# Target: claude (validation — native layer, nothing generated)
# --------------------------------------------------------------------------
def check_claude(roles, agents):
    """Every agent's tools ⊆ its role envelope (+ declared exception)."""
    problems = []
    for name, agent in sorted(agents.items()):
        role = roles.get(agent["tier"])
        if role is None:
            problems.append(f"{name}: tier '{agent['tier']}' has no roles/{agent['tier']}.yaml")
            continue
        if role["envelope"] == "all":
            continue
        if agent["tools"] == "all":
            problems.append(
                f"{name}: unrestricted tools but role '{role['name']}' has a bounded envelope"
            )
            continue
        allowed = set(role["envelope"])
        allowed |= set(role["exceptions"].get(name, {}).get("add", []))
        # mcp:<server> tools are allowed only where the role permits network.
        for t in agent["tools"]:
            if t.startswith("mcp:"):
                if _network_level(role) != "true":
                    problems.append(
                        f"{name}: uses {t} but role '{role['name']}' does not declare "
                        f"network: true (MCP servers can mutate external state)"
                    )
                continue
            if t not in allowed:
                problems.append(
                    f"{name}: tool '{t}' exceeds role '{role['name']}' envelope "
                    f"(declare an exception in roles/{role['name']}.yaml or remove the tool)"
                )
        if not role["write"]:
            excess = (_WRITE_TOOLS & set(agent["tools"])) - allowed
            if excess:
                problems.append(f"{name}: write tools {sorted(excess)} in a write:false role")
    for role in roles.values():
        for exc_agent in role["exceptions"]:
            if exc_agent not in agents:
                problems.append(
                    f"roles/{role['name']}.yaml: exception for unknown agent '{exc_agent}'"
                )
            elif agents[exc_agent]["tier"] != role["name"]:
                problems.append(
                    f"roles/{role['name']}.yaml: exception '{exc_agent}' is tier "
                    f"'{agents[exc_agent]['tier']}', not '{role['name']}'"
                )
    return problems


# --------------------------------------------------------------------------
# Target: codex
# --------------------------------------------------------------------------
def emit_codex(roles):
    lines = [
        "# Generated by `aif compile` from roles/*.yaml — do not hand-edit.",
        "# One Codex profile per agent role. Select with: codex --profile <role>",
        "# Mapping: write:false roles -> read-only sandbox; write:true -> workspace-write;",
        "# network follows the role's network: flag. Codex cannot scope individual",
        "# tools the way Claude frontmatter can, so the sandbox IS the envelope.",
        "",
    ]
    for rname in _ROLE_ORDER:
        role = roles[rname]
        lines.append(f"[profiles.{rname}]")
        lines.append(f"# {role['summary']}")
        net = _network_level(role)
        if role["write"]:
            lines.append('sandbox_mode = "workspace-write"')
            lines.append('approval_policy = "on-request"')
            lines.append("[profiles.%s.sandbox_workspace_write]" % rname)
            lines.append("network_access = %s" % ("true" if net != "false" else "false"))
            if net == "read-only":
                lines.append("# role policy: network is READ-ONLY (dependency fetch etc.) — Codex")
                lines.append("# cannot enforce read-vs-write network; the sandbox flag above is the")
                lines.append("# closest mapping. Gateway enforcement: see compiled/cedar/.")
        else:
            lines.append('sandbox_mode = "read-only"')
            lines.append('approval_policy = "never"')
            if net == "read-only":
                lines.append("# role policy permits READ-ONLY network (e.g. gh pr view); Codex's")
                lines.append("# read-only sandbox blocks network, so such commands will surface as")
                lines.append("# approval requests — approve reads only.")
        lines.append("")
    return "\n".join(lines)


# --------------------------------------------------------------------------
# Target: copilot
# --------------------------------------------------------------------------
def emit_copilot(roles):
    lines = [
        "<!-- Generated by `aif compile` from roles/*.yaml — do not hand-edit.",
        "     Paste (or reference) this block from .github/copilot-instructions.md.",
        "     Copilot has no per-role enforcement surface: these boundaries are",
        "     CONVENTION for the model to follow. Hard enforcement requires a",
        "     gateway (see compiled/cedar/). -->",
        "",
        "## Agent role boundaries",
        "",
        "When acting in one of these roles, stay inside its boundary:",
        "",
    ]
    for rname in _ROLE_ORDER:
        role = roles[rname]
        env = "full tool access" if role["envelope"] == "all" else ", ".join(role["envelope"])
        write = "may modify files" if role["write"] else "MUST NOT modify any file"
        net_desc = {
            "false": "no network access",
            "read-only": "read-only network (fetching context/dependencies; never posting)",
            "true": "full network (may post to forges/channels)",
        }[_network_level(role)]
        lines.append(f"- **{rname}** — {role['summary']} Tools: {env}. This role {write}; {net_desc}.")
        for agent, exc in sorted(role["exceptions"].items()):
            lines.append(
                f"  - Exception: `{agent}` may additionally use "
                f"{', '.join(exc['add'])} — {exc['reason']}."
            )
    lines.append("")
    return "\n".join(lines)


# --------------------------------------------------------------------------
# Target: cedar
# --------------------------------------------------------------------------
_CEDAR_ACTION = {
    "read": "ReadFile", "grep": "SearchCode", "glob": "ListFiles",
    "bash": "ExecuteCommand", "edit": "WriteFile", "write": "WriteFile",
    "monitor": "MonitorProcess",
}


def emit_cedar_schema():
    return """// Generated by `aif compile` from roles/*.yaml — do not hand-edit.
// Minimal schema for agent-capability enforcement at a gateway.
entity Role;
entity Agent in [Role];
entity Repo;
action ReadFile, SearchCode, ListFiles, ExecuteCommand, WriteFile,
       MonitorProcess, NetworkRead, NetworkWrite appliesTo {
    principal: [Agent],
    resource: [Repo]
};
"""


def emit_cedar_policies(roles):
    out = [
        "// Generated by `aif compile` from roles/*.yaml — do not hand-edit.",
        "// One permit per role (envelope semantics) + explicit forbids for",
        "// write:false roles. Agent exceptions are per-principal permits.",
        "",
    ]
    for rname in _ROLE_ORDER:
        role = roles[rname]
        if role["envelope"] == "all":
            actions = sorted(set(_CEDAR_ACTION.values()))
        else:
            actions = sorted({_CEDAR_ACTION[t] for t in role["envelope"]})
        net = _network_level(role)
        if net == "read-only":
            actions = sorted(set(actions) | {"NetworkRead"})
        elif net == "true":
            actions = sorted(set(actions) | {"NetworkRead", "NetworkWrite"})
        action_list = ", ".join(f'Action::"{a}"' for a in actions)
        out.append(f"// role: {rname} — {role['summary']}")
        out.append(
            f'permit(principal in Role::"{rname}", action in [{action_list}], resource);'
        )
        if not role["write"]:
            exceptions = sorted(role["exceptions"])
            if exceptions:
                unless = " && ".join(
                    f'principal != Agent::"{a}"' for a in exceptions
                )
                out.append(
                    f'forbid(principal in Role::"{rname}", action == Action::"WriteFile", resource) '
                    f"when {{ {unless} }};"
                )
                for agent, exc in sorted(role["exceptions"].items()):
                    out.append(f"// exception: {agent} — {exc['reason']}")
                    out.append(
                        f'permit(principal == Agent::"{agent}", '
                        f'action == Action::"WriteFile", resource);'
                    )
            else:
                out.append(
                    f'forbid(principal in Role::"{rname}", action == Action::"WriteFile", resource);'
                )
        out.append("")
    return "\n".join(out)



# --------------------------------------------------------------------------
# Target: claude settings overlays (consumer-repo / headless permission blocks)
# --------------------------------------------------------------------------
# One .claude settings JSON per role, enforcing the role envelope at the
# HARNESS level — the piece agent frontmatter can't cover when a role runs
# headless (CI jobs, cron, sandboxes; see references/trigger-recipes.md).
# Apply with `claude --settings compiled/claude/settings-<role>.json` or copy
# into the sandbox checkout's .claude/settings.json.

_BASH_READ = [
    "Bash(ls:*)", "Bash(find:*)", "Bash(grep:*)", "Bash(wc:*)",
    "Bash(head:*)", "Bash(tail:*)", "Bash(pwd)", "Bash(which:*)",
    "Bash(git status:*)", "Bash(git diff:*)", "Bash(git log:*)",
    "Bash(git show:*)", "Bash(git branch:*)",
    "Bash(go test:*)", "Bash(go vet:*)", "Bash(gofmt:*)",
    "Bash(npm test:*)", "Bash(pnpm test:*)", "Bash(pytest:*)",
    "Bash(python -m pytest:*)", "Bash(cargo test:*)",
    "Bash(make test:*)", "Bash(make lint:*)", "Bash(ruff check:*)",
]
_BASH_NET_READ = [
    "Bash(git fetch:*)", "Bash(git pull:*)",
    "Bash(gh pr view:*)", "Bash(gh pr diff:*)", "Bash(gh pr checks:*)",
    "Bash(gh pr list:*)", "Bash(gh issue view:*)", "Bash(gh issue list:*)",
    "Bash(gh search:*)", "Bash(gh run view:*)", "Bash(gh run list:*)",
]
_BASH_WRITE_LOCAL = [
    "Bash(git add:*)", "Bash(git commit:*)", "Bash(git checkout:*)",
    "Bash(git worktree:*)", "Bash(git stash:*)", "Bash(git restore:*)",
    "Bash(mkdir:*)", "Bash(cp:*)", "Bash(mv:*)", "Bash(touch:*)",
    "Bash(npm run:*)", "Bash(pnpm run:*)", "Bash(make build:*)",
    "Bash(go build:*)", "Bash(cargo build:*)", "Bash(ruff format:*)",
]
_BASH_NET_WRITE = [
    "Bash(git push:*)",
    "Bash(gh pr create:*)", "Bash(gh pr ready:*)", "Bash(gh pr edit:*)",
    "Bash(gh pr comment:*)", "Bash(gh issue create:*)", "Bash(gh issue comment:*)",
]
_WRITE_TOOL_RULES = ["Edit", "Write", "NotebookEdit"]
_NET_TOOL_RULES = ["WebFetch", "WebSearch"]
_ASK_DESTRUCTIVE = [
    "Bash(git push --force:*)", "Bash(git reset --hard:*)",
    "Bash(git clean -f:*)", "Bash(git branch -D:*)",
    "Bash(gh pr merge:*)", "Bash(gh pr close:*)", "Bash(gh release:*)",
    "Bash(rm -rf:*)", "Bash(rm -f:*)",
]


def emit_claude_settings(role):
    net = _network_level(role)
    comment = (
        f"Generated by `aif compile` from roles/{role['name']}.yaml — do not hand-edit. "
        f"Harness-level enforcement of the {role['name']} role for headless/CI/sandboxed "
        f"sessions (see references/trigger-recipes.md). {role['summary']} "
        f"Apply with: claude --settings <this file>, or copy into the sandbox "
        f"checkout's .claude/settings.json."
    )
    allow = list(_BASH_READ)
    deny = []
    ask = []
    if net != "false":
        allow += _BASH_NET_READ
        allow += _NET_TOOL_RULES        # WebFetch/WebSearch are read-only network
    else:
        deny += _NET_TOOL_RULES
        deny += _BASH_NET_READ
    if role["write"]:
        allow += _BASH_WRITE_LOCAL
        default_mode = "acceptEdits"
        ask += _ASK_DESTRUCTIVE
    else:
        deny += _WRITE_TOOL_RULES
        deny += ["Bash(git add:*)", "Bash(git commit:*)", "Bash(rm:*)",
                 "Bash(git checkout:*)", "Bash(git reset:*)"]
        default_mode = "default"
    if net == "true":
        allow += _BASH_NET_WRITE
        if role["write"]:
            pass  # ask list already carries the destructive net ops
    else:
        deny += _BASH_NET_WRITE
    payload = {
        "_comment": comment,
        "permissions": {
            "defaultMode": default_mode,
            "allow": sorted(set(allow)),
            "ask": sorted(set(ask)),
            "deny": sorted(set(deny)),
        },
    }
    return json.dumps(payload, indent=2) + "\n"


# --------------------------------------------------------------------------
# Driver
# --------------------------------------------------------------------------
def _outputs(roles):
    out = {
        os.path.join("compiled", "claude", f"settings-{rname}.json"): emit_claude_settings(roles[rname])
        for rname in _ROLE_ORDER
    }
    out.update({
        os.path.join("compiled", "codex", "config.toml"): emit_codex(roles),
        os.path.join("compiled", "copilot", "copilot-instructions-roles.md"): emit_copilot(roles),
        os.path.join("compiled", "cedar", "roles.cedarschema"): emit_cedar_schema(),
        os.path.join("compiled", "cedar", "roles.cedar"): emit_cedar_policies(roles),
    })
    return out


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    check_only = "--check" in argv
    root = _repo_root()
    try:
        roles = load_roles(root)
        agents = load_agents(root)
        problems = check_claude(roles, agents)
    except CompileError as exc:
        print(f"aif compile: {exc}", file=sys.stderr)
        return 2
    for p in problems:
        print(f"claude: {p}", file=sys.stderr)

    drift = []
    for rel, content in _outputs(roles).items():
        path = os.path.join(root, rel)
        if check_only:
            try:
                with open(path, encoding="utf-8") as fh:
                    on_disk = fh.read()
            except OSError:
                on_disk = None
            if on_disk != content:
                drift.append(rel)
        else:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(content)
            print(f"wrote {rel}")
    for rel in drift:
        print(f"drift: {rel} is stale — run `aif compile` to regenerate", file=sys.stderr)
    if problems or drift:
        return 1
    if check_only:
        print("compile check: agents within role envelopes; compiled outputs current")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
