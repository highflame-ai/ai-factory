"""Tests for aif packs — codeoid pack validator."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import packs  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
AIF_SDLC = os.path.join(ROOT, "packs", "aif-sdlc")
ORG_DEV = os.path.join(ROOT, "packs", "org-dev")


def test_shipped_pack_is_valid():
    assert packs.validate_pack(AIF_SDLC) == []


def test_org_dev_pack_is_valid():
    assert packs.validate_pack(ORG_DEV) == []


def test_block_map_item_with_literal_template():
    pk = packs.parse_pack(os.path.join(ORG_DEV, "pack.yaml"))
    verify = next(s for s in pk["skills"] if isinstance(s, dict) and s.get("id") == "verify")
    assert verify["kind"] == "prompt"
    assert "\n" in verify["template"] and "regression" in verify["template"]


def test_parse_block_item_literal(tmp_path):
    p = tmp_path / "pack.yaml"
    p.write_text(
        "schema: codeoid/pack@v1\n"
        "skills:\n"
        "  - id: v\n"
        "    kind: prompt\n"
        "    template: |\n"
        "      line one\n"
        "\n"
        "      line three\n"
        "  - { id: s, kind: slash, command: /review }\n")
    pk = packs.parse_pack(str(p))
    assert pk["skills"][0] == {"id": "v", "kind": "prompt", "template": "line one\n\nline three"}
    assert pk["skills"][1]["id"] == "s"


def test_parse_extracts_pipeline():
    pk = packs.parse_pack(os.path.join(AIF_SDLC, "pack.yaml"))
    assert pk["schema"] == "codeoid/pack@v1"
    assert {s["id"] for s in pk["skills"]} >= {"spec", "review", "wrapup"}
    assert any(ph["role"] == "reviewer" for ph in pk["phases"])


def test_unknown_phase_role_flagged(tmp_path):
    d = tmp_path / "bad"
    (d / "roles").mkdir(parents=True)
    (d / "ETHOS.md").write_text("x")
    (d / "roles" / "reviewer.yaml").write_text(
        "name: reviewer\nsummary: r\nwrite: false\nenvelope:\n  - read\n")
    (d / "pack.yaml").write_text(
        "schema: codeoid/pack@v1\nid: bad\nname: Bad\nversion: 0.0.1\n"
        "constitution: ./ETHOS.md\nroles:\n  - ./roles/reviewer.yaml\n"
        "skills:\n  - { id: review, kind: slash, command: /review }\n"
        "phases:\n  - { id: review, skill: review, role: ghost }\n")
    problems = packs.validate_pack(str(d))
    assert any("unknown role 'ghost'" in p for p in problems)


def test_flow_map_parser():
    m = packs._parse_flow_map("{ id: implement, gate: t, onFail: { retry: 2 } }")
    assert m["id"] == "implement" and m["gate"] == "t"


def test_index_freshness_catches_version_drift(tmp_path):
    import shutil
    shutil.copytree(os.path.join(ROOT, "packs"), tmp_path / "packs")
    py = tmp_path / "packs" / "aif-sdlc" / "pack.yaml"
    # Bump to a version the shipped index can never carry — hardcoding the
    # "next" version made this test a no-op the day the pack actually reached it.
    import re
    drifted = re.sub(r"^version: .*$", "version: 99.0.0", py.read_text(), count=1, flags=re.M)
    assert drifted != py.read_text()
    py.write_text(drifted)
    manifests = {str(tmp_path / "packs" / "aif-sdlc"): packs.parse_pack(str(py))}
    problems = packs.validate_index(str(tmp_path / "packs"), manifests)
    assert any("version" in p for p in problems)


def test_shipped_index_is_fresh():
    d = os.path.join(ROOT, "packs", "aif-sdlc")
    manifests = {d: packs.parse_pack(os.path.join(d, "pack.yaml"))}
    assert packs.validate_index(os.path.join(ROOT, "packs"), manifests) == []
