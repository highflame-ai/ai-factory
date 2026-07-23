"""Tests for perm_audit — the standing-grant risk classifier.

Encodes the reviewed classification contract: destructive/credential grants are
remove-class in ANY common spelling (no `rm -fr` bypass), benign lookalikes
(.env.example, $MONKEY, docs/credentials.md) never flag, ambiguous .env access
is review-class (surfaced, never doctor-red), and deliberate keeps live in
.claude/permissions-audit-exemptions.json as exempt-class findings.
"""

import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import perm_audit as pa  # noqa: E402


def test_remove_class_patterns():
    for rule in (
        "Bash(rm -rf build)",
        "Bash(rm -fr build)",            # reversed flags — must not bypass
        "Bash(rm -f -r build)",          # split flags
        "Bash(rm --recursive --force x)",
        "Bash(git push --force origin main)",
        "Bash(git push origin +main)",   # refspec force-push
        'Bash(curl -H "Authorization: Bearer $API_TOKEN" https://x)',
        "Bash(echo $DB_PASSWORD)",
        "Bash(cat ~/.aws/credentials)",
        "Bash(cat ~/.ssh/id_rsa)",
        "Bash(security find-generic-password -s x)",
    ):
        klass, why = pa.classify_rule(rule)
        assert klass == "remove", f"{rule} -> {klass}"
        assert why


def test_benign_lookalikes_are_keep():
    # The false positives the adversarial review reproduced — must stay keep.
    for rule in (
        "Read(.env.example)",
        "Bash(cp .env.example .env.sample)",
        "Bash(echo $MONKEY)",                 # contains KEY, not a key
        "Bash(setxkbmap $KEYBOARD_LAYOUT)",   # starts with KEY, not a key
        "Read(docs/credentials.md)",
        "Bash(git push:*)",                   # plain push is not force-push
        "Bash(rm file.txt)",                  # non-recursive rm
        "Bash(make build:*)",
        "Bash(gh pr view:*)",
    ):
        assert pa.classify_rule(rule)[0] is None, rule


def test_env_file_access_is_review_not_remove():
    # cat .env reads secrets; cp .env.example .env is setup — regex can't tell,
    # so both surface for a human without failing doctor.
    for rule in ("Bash(cat .env)", "Bash(cp .env.example .env)"):
        assert pa.classify_rule(rule)[0] == "review", rule


def test_review_class_broad_wildcards():
    for rule in ("Bash(*)", "Bash(:*)", "Read(*)"):
        assert pa.classify_rule(rule)[0] == "review", rule


def test_audit_dir_merges_sources_and_flags(tmp_path):
    cd = tmp_path / ".claude"
    cd.mkdir()
    (cd / "settings.json").write_text(json.dumps(
        {"permissions": {"allow": ["Bash(make build:*)", "Bash(rm -rf:*)"]}}))
    (cd / "settings.local.json").write_text(json.dumps(
        {"permissions": {"allow": ["Bash(rm -rf:*)", "Bash(cat ~/.ssh/id_rsa)"]}}))
    findings = {f["rule"]: f for f in pa.audit_dir(str(tmp_path))}
    assert findings["Bash(rm -rf:*)"]["class"] == "remove"
    # a rule in both files carries both sources (dedup would mislead cleanup)
    assert "settings.json" in findings["Bash(rm -rf:*)"]["source"]
    assert "settings.local.json" in findings["Bash(rm -rf:*)"]["source"]
    assert "Bash(make build:*)" not in findings


def test_exemptions_reclassify_without_failing(tmp_path):
    cd = tmp_path / ".claude"
    cd.mkdir()
    (cd / "settings.json").write_text(json.dumps(
        {"permissions": {"allow": ["Bash(rm -rf:*)"]}}))
    (cd / "permissions-audit-exemptions.json").write_text(json.dumps(
        {"exempt": {"Bash(rm -rf:*)": "scoped to build dirs by convention"}}))
    findings = pa.audit_dir(str(tmp_path))
    assert findings[0]["class"] == "exempt"
    assert "scoped to build dirs" in findings[0]["why"]


def test_malformed_settings_is_surfaced_not_certified_clean(tmp_path):
    cd = tmp_path / ".claude"
    cd.mkdir()
    (cd / "settings.json").write_text("{not json")
    findings = pa.audit_dir(str(tmp_path))
    assert any(f["class"] == "review" and "could not audit" in f["why"] for f in findings)


def test_no_settings_is_clean(tmp_path):
    assert not pa.has_settings(str(tmp_path))
    assert pa.audit_dir(str(tmp_path)) == []


def test_non_object_json_is_surfaced_not_crashed(tmp_path):
    # valid JSON that isn't a settings object (gemini-code-assist finding on PR #3)
    cd = tmp_path / ".claude"
    cd.mkdir()
    (cd / "settings.json").write_text("[]")
    findings = pa.audit_dir(str(tmp_path))
    assert any(f["class"] == "review" and "not a settings object" in f["why"] for f in findings)
    (cd / "settings.json").write_text('{"permissions": []}')  # permissions wrong type
    assert isinstance(pa.audit_dir(str(tmp_path)), list)  # no crash
