"""Tests for aif compile — the roles/*.yaml capability compiler."""

import os
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import compile as roles_compile  # noqa: E402


@pytest.fixture()
def roles(repo_root):
    return roles_compile.load_roles(repo_root)


@pytest.fixture()
def agents(repo_root):
    return roles_compile.load_agents(repo_root)


def test_all_five_roles_load(roles):
    assert set(roles) >= set(roles_compile._ROLE_ORDER)
    for role in roles.values():
        assert role["summary"]
        assert role["envelope"] == "all" or role["envelope"]


def test_shipped_agents_within_envelopes(roles, agents):
    assert roles_compile.check_claude(roles, agents) == []


def test_envelope_violation_detected(roles, agents):
    agents = dict(agents)
    agents["correctness-reviewer"] = {"tier": "reviewer", "tools": ["read", "write"]}
    problems = roles_compile.check_claude(roles, agents)
    assert any("exceeds role" in p for p in problems)


def test_unrestricted_agent_in_bounded_role_detected(roles, agents):
    agents = dict(agents)
    agents["adversary"] = {"tier": "reviewer", "tools": "all"}
    problems = roles_compile.check_claude(roles, agents)
    assert any("unrestricted" in p for p in problems)


def test_exception_for_unknown_agent_detected(roles, agents):
    roles = {k: dict(v) for k, v in roles.items()}
    roles["reviewer"] = dict(roles["reviewer"])
    roles["reviewer"]["exceptions"] = dict(roles["reviewer"]["exceptions"])
    roles["reviewer"]["exceptions"]["ghost-agent"] = {"add": ["edit"], "reason": "x"}
    problems = roles_compile.check_claude(roles, agents)
    assert any("unknown agent 'ghost-agent'" in p for p in problems)


def test_mcp_requires_network_role(roles, agents):
    agents = dict(agents)
    agents["quality-reviewer"] = {"tier": "reviewer", "tools": ["read", "mcp:slack"]}
    problems = roles_compile.check_claude(roles, agents)
    assert any("network: true" in p for p in problems)


def test_outputs_deterministic(roles):
    a = roles_compile._outputs(roles)
    b = roles_compile._outputs(roles)
    assert a == b


def test_compiled_outputs_current(repo_root, roles):
    """The committed compiled/ artifacts must match a fresh generation."""
    for rel, content in roles_compile._outputs(roles).items():
        path = os.path.join(repo_root, rel)
        assert os.path.isfile(path), f"{rel} missing — run `aif compile`"
        with open(path, encoding="utf-8") as fh:
            assert fh.read() == content, f"{rel} stale — run `aif compile`"


def test_cedar_forbids_write_for_readonly_roles(roles):
    policies = roles_compile.emit_cedar_policies(roles)
    for rname in ("reviewer", "scanner", "explorer"):
        assert f'Role::"{rname}"' in policies
    assert 'forbid(principal in Role::"scanner", action == Action::"WriteFile"' in policies
    # the one shipped exception is carried as a per-principal permit
    assert 'permit(principal == Agent::"gemini-reviewer"' in policies


def test_codex_sandbox_mapping(roles):
    toml = roles_compile.emit_codex(roles)
    assert '[profiles.reviewer]' in toml and 'sandbox_mode = "read-only"' in toml
    assert '[profiles.implementer]' in toml and 'sandbox_mode = "workspace-write"' in toml


def test_role_file_parser_rejects_unknown_tool(tmp_path):
    bad = tmp_path / "bad.yaml"
    bad.write_text("name: x\nsummary: y\nwrite: false\nenvelope:\n  - laser\n")
    with pytest.raises(roles_compile.CompileError):
        roles_compile.parse_role_file(str(bad))


def test_claude_settings_overlays(roles):
    import json as _json
    rev = _json.loads(roles_compile.emit_claude_settings(roles["reviewer"]))
    assert rev["permissions"]["defaultMode"] == "default"
    for rule in ("Edit", "Write", "NotebookEdit", "Bash(git push:*)", "Bash(git commit:*)"):
        assert rule in rev["permissions"]["deny"]
    assert "Bash(gh pr view:*)" in rev["permissions"]["allow"]      # read-only network
    assert "WebFetch" in rev["permissions"]["allow"]

    scan = _json.loads(roles_compile.emit_claude_settings(roles["scanner"]))
    assert "WebFetch" in scan["permissions"]["deny"]                # network: false
    assert "Bash(gh pr view:*)" in scan["permissions"]["deny"]

    impl = _json.loads(roles_compile.emit_claude_settings(roles["implementer"]))
    assert "Bash(git commit:*)" in impl["permissions"]["allow"]     # write: true
    assert "Bash(git push:*)" in impl["permissions"]["deny"]        # network: read-only

    orch = _json.loads(roles_compile.emit_claude_settings(roles["orchestrator"]))
    assert "Bash(git push:*)" in orch["permissions"]["allow"]       # network: true
    assert "Bash(git push --force:*)" in orch["permissions"]["ask"]
    assert orch["permissions"]["defaultMode"] == "acceptEdits"
