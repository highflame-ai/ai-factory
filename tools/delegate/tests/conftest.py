import os
import subprocess
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


@pytest.fixture(scope="session")
def partials_dir():
    """Absolute path to the repo's `partials/` directory.

    File-anchored: this conftest lives at tools/delegate/tests/, so the repo
    root is three levels up. Anchoring on __file__ (not `git rev-parse
    --show-toplevel`) keeps the tests correct when the checkout is nested
    inside another git repo or is not a git repo at all.
    """
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
    pdir = os.path.join(root, "skills", "partials")
    if not os.path.isdir(pdir):
        pytest.skip(f"partials/ not found at {pdir} — unexpected checkout layout")
    return pdir
