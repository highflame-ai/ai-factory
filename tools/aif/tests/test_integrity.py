"""Tests for `aif check` — the unified integrity gate.

The load-bearing promise: exit is non-zero iff a gate that RAN failed; a
skipped runner never masks failure. Tested with stubbed gates (no nested
subprocess re-runs of the real suites — those already run as the gate itself).
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import integrity as aif_check  # noqa: E402


def test_failed_gate_fails_the_run(monkeypatch):
    calls = []

    def fake_run(cmd, cwd):
        calls.append(cmd)
        return (1, "boom") if "lint-skills" in " ".join(cmd) else (0, "")

    monkeypatch.setattr(aif_check, "_run", fake_run)
    assert aif_check.main(["--quick"]) == 1
    assert calls, "no gates ran"


def test_all_pass_returns_zero(monkeypatch):
    monkeypatch.setattr(aif_check, "_run", lambda cmd, cwd: (0, ""))
    assert aif_check.main(["--quick"]) == 0


def test_skipped_runner_does_not_mask_failure(monkeypatch):
    # full mode with every optional runner "absent": only stdlib gates run,
    # and a failing one still fails the whole check.
    monkeypatch.setattr(aif_check, "_pytest_available", lambda: False)
    monkeypatch.setattr(aif_check, "_have", lambda cmd: False)
    monkeypatch.setattr(
        aif_check, "_run",
        lambda cmd, cwd: (2, "drift") if "compile" in cmd else (0, ""),
    )
    assert aif_check.main([]) == 1


def test_unknown_argument_is_a_usage_error():
    assert aif_check.main(["--qick"]) == 2


def test_repo_root_resolves_to_toolkit():
    root = aif_check._repo_root()
    assert os.path.isfile(os.path.join(root, "tools", "aif", "aif.py"))
    assert os.path.isdir(os.path.join(root, "roles"))
