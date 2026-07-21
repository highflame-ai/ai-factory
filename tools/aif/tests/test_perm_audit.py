"""Tests for perm_audit — the standing-grant risk classifier."""

import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import perm_audit as pa  # noqa: E402


def test_remove_class_patterns():
    for rule in (
        "Bash(rm -rf build)",
        "Bash(git push --force origin main)",
        'Bash(curl -H "Authorization: Bearer $API_TOKEN" https://x)',
        "Bash(cat ~/.aws/credentials)",
        "Bash(cat .env)",
        "Bash(security find-generic-password -s x)",
    ):
        klass, why = pa.classify_rule(rule)
        assert klass == "remove", f"{rule} -> {klass}"
        assert why


def test_review_class_broad_wildcards():
    for rule in ("Bash(*)", "Bash(:*)", "Read(*)"):
        assert pa.classify_rule(rule)[0] == "review", rule


def test_keep_class_bounded_rules():
    for rule in ("Bash(make build:*)", "Bash(gh pr view:*)", "Read(src/**)",
                 "Bash(go test:*)"):
        assert pa.classify_rule(rule)[0] is None, rule


def test_audit_dir_merges_and_flags(tmp_path):
    cd = tmp_path / ".claude"
    cd.mkdir()
    (cd / "settings.json").write_text(json.dumps(
        {"permissions": {"allow": ["Bash(make build:*)", "Bash(rm -rf:*)"]}}))
    (cd / "settings.local.json").write_text(json.dumps(
        {"permissions": {"allow": ["Bash(cat ~/.ssh/id_rsa)"]}}))
    findings = pa.audit_dir(str(tmp_path))
    classes = {f["rule"]: f["class"] for f in findings}
    assert classes.get("Bash(rm -rf:*)") == "remove"
    assert classes.get("Bash(cat ~/.ssh/id_rsa)") == "remove"
    assert "Bash(make build:*)" not in classes  # keep-class not reported


def test_no_settings_is_clean(tmp_path):
    assert not pa.has_settings(str(tmp_path))
    assert pa.audit_dir(str(tmp_path)) == []
