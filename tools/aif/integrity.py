#!/usr/bin/env python3
"""aif check — the single integrity gate for the toolkit repo.

Runs every structural guard the toolkit ships, in one command, so CI and
pre-commit don't have to enumerate them (and can't drift out of sync with what
the toolkit actually guarantees). Each gate is run only if its runner is
present; a missing runner is a SKIP with a notice, never a failure — same
honesty rule as `aif doctor`. Exit is non-zero iff a gate that RAN failed.

Gates, in order:
  lint-skills        python3 tools/lint-skills/check.py      (stdlib — always runs)
  compile            aif compile --check                     (stdlib — always runs)
  agents-render      aif agents render --check               (stdlib — always runs)
  packs              aif packs.py (validate codeoid packs)   (skip if no packs/)
  pytest             python3 -m pytest <suites>              (skip if pytest absent)
  partials           sh skills/partials/tests/run.sh         (skip if sh absent)
  workflows          node --test skills/workflows/tests/     (skip if node absent)

`--quick` runs only the always-available stdlib gates — lint-skills, compile,
agents-render, and pack validation when packs/ exists — skipping the test
runners (the pre-commit default). Full run is the CI default.
"""

import os
import subprocess
import sys

_TTY = sys.stdout.isatty()
_GREEN = "\033[0;32m" if _TTY else ""
_RED = "\033[0;31m" if _TTY else ""
_DIM = "\033[2m" if _TTY else ""
_YEL = "\033[0;33m" if _TTY else ""
_NC = "\033[0m" if _TTY else ""


def _repo_root():
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(os.path.dirname(here))


def _have(cmd):
    from shutil import which
    return which(cmd) is not None


def _run(cmd, cwd):
    """Run a gate; return (exit_code, combined_output)."""
    proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    return proc.returncode, (proc.stdout or "") + (proc.stderr or "")


def _pytest_available():
    code, _ = _run([sys.executable, "-m", "pytest", "--version"], _repo_root())
    return code == 0


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    unknown = [a for a in argv if a not in ("--quick",)]
    if unknown:
        print(f"aif check: unknown argument(s): {' '.join(unknown)} (usage: aif check [--quick])",
              file=sys.stderr)
        return 2
    quick = "--quick" in argv
    root = _repo_root()
    py = sys.executable

    # (name, argv, cwd, runnable_predicate). Predicate None = always runs.
    gates = [
        ("lint-skills",
         [py, "tools/lint-skills/check.py"], root, None),
        ("compile",
         [py, "tools/aif/aif.py", "compile", "--check"], root, None),
        ("agents-render",
         [py, "tools/aif/aif.py", "agents", "render", "--check"], root, None),
        ("packs",
         [py, "tools/aif/packs.py"], root,
         lambda: os.path.isdir(os.path.join(root, "packs"))),
    ]
    if not quick:
        gates += [
            ("pytest",
             [py, "-m", "pytest",
              "tools/aif/tests/", "tools/lint-skills/tests/", "tools/delegate/tests/",
              "-q"],
             root, _pytest_available),
            ("partials",
             ["sh", "skills/partials/tests/run.sh"], root,
             lambda: _have("sh")),
            ("workflows",
             ["node", "--test", "tests/helpers.test.js"],
             os.path.join(root, "skills", "workflows"),
             lambda: _have("node")),
        ]

    failed, skipped, passed = [], [], []
    for name, cmd, cwd, runnable in gates:
        if runnable is not None and not runnable():
            skipped.append(name)
            print(f"{_DIM}[skip]{_NC} {name} (runner not available)")
            continue
        code, out = _run(cmd, cwd)
        if code == 0:
            passed.append(name)
            print(f"{_GREEN}[pass]{_NC} {name}")
        else:
            failed.append(name)
            print(f"{_RED}[fail]{_NC} {name}")
            # Surface the gate's own output — it already prints copy-pasteable
            # remediation (linter lines, drift diffs, test failures).
            for line in out.strip().splitlines():
                print(f"    {line}")

    print()
    summary = f"aif check: {len(passed)} passed"
    if skipped:
        summary += f", {len(skipped)} skipped ({', '.join(skipped)})"
    if failed:
        summary += f", {_RED}{len(failed)} failed ({', '.join(failed)}){_NC}"
        sys.stdout.flush()
        print(summary, file=sys.stderr)
        return 1
    print(f"{_GREEN}{summary}{_NC}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
