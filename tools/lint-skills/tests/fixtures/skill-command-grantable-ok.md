# Fixture: inline substitutions that stay one exact rule — no findings (codeoid #348)

- Specs: !`grep -rl --include=requirement.md 'status: draft' .aif/specs 2>/dev/null | head -20 || echo "No active specs"`
- Repo: !`git rev-parse --show-toplevel 2>/dev/null || echo "(not a git repo)"`
- Status: !`git status --short 2>/dev/null || echo clean`
