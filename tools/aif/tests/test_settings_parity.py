"""Settings sync-surface parity.

Three settings files ship in this repo:

  1. ``skills/templates/claude-settings-template.json`` — copied into consumer
     repos by ``/init`` (rich allow list + ask list).
  2. ``skills/templates/settings.example.json`` — the fleet-distribution source
     read by ``tools/fleet/distribute-settings.sh`` (lean safe-baseline allow).
  3. ``.claude/settings.json`` — this repo's own settings (dogfoods #1).

The allow lists intentionally differ. The ``hooks`` block and the
``permissions.deny`` list must NOT differ — they are the security-relevant
surfaces, and a drifted copy means a repo fleet silently running different
gates than the template documents. This test is the guard.
"""

import json
import os

import pytest

ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
)

TEMPLATE = os.path.join(ROOT, "skills", "templates", "claude-settings-template.json")
EXAMPLE = os.path.join(ROOT, "skills", "templates", "settings.example.json")
REPO_OWN = os.path.join(ROOT, ".claude", "settings.json")


def _load(path):
    if not os.path.isfile(path):
        pytest.skip(f"{path} not found — unexpected checkout layout")
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def test_hooks_blocks_identical():
    template, example, own = _load(TEMPLATE), _load(EXAMPLE), _load(REPO_OWN)
    assert template["hooks"] == example["hooks"], (
        "hooks drift between claude-settings-template.json and "
        "settings.example.json — update both in the same commit"
    )
    assert template["hooks"] == own["hooks"], (
        "hooks drift between the template and this repo's own .claude/settings.json"
    )


def test_deny_lists_identical():
    template, example, own = _load(TEMPLATE), _load(EXAMPLE), _load(REPO_OWN)
    assert template["permissions"]["deny"] == example["permissions"]["deny"]
    assert template["permissions"]["deny"] == own["permissions"]["deny"]


def test_example_allow_is_subset_of_template():
    # The fleet baseline must never allow something the richer template doesn't.
    template, example = _load(TEMPLATE), _load(EXAMPLE)
    extra = set(example["permissions"]["allow"]) - set(template["permissions"]["allow"])
    assert not extra, f"settings.example.json allows entries the template doesn't: {sorted(extra)}"
