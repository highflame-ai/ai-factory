"""Test fixtures for tools/aif — mirrors tools/delegate/tests/conftest.py.

Inserts the parent dir (tools/aif) onto sys.path so `import aif`,
`import doctor`, `import checks` resolve regardless of cwd.
"""
import os
import subprocess
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


@pytest.fixture(scope="session")
def repo_root():
    """Absolute path to the toolkit checkout root.

    File-anchored (this conftest lives at tools/aif/tests/, so the root is
    three levels up) rather than `git rev-parse --show-toplevel`: the git
    answer binds to the ENCLOSING repo when this checkout is nested inside
    another git repo, and to nothing at all pre-`git init`.
    """
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
    if not os.path.isdir(os.path.join(root, "agents")):
        pytest.skip(f"agents/ not found under {root} — unexpected checkout layout")
    return root
