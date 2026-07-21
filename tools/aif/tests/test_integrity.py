"""Tests for `aif check` — the unified integrity gate."""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import integrity as aif_check  # noqa: E402


def test_quick_gates_pass_on_clean_repo():
    # The three stdlib gates must pass on the committed tree.
    rc = aif_check.main(["--quick"])
    assert rc == 0


def test_repo_root_resolves_to_toolkit():
    root = aif_check._repo_root()
    assert os.path.isfile(os.path.join(root, "tools", "aif", "aif.py"))
    assert os.path.isdir(os.path.join(root, "roles"))
