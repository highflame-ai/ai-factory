# Commit Prefix Check

`hooks/commit-prefix-check.sh` is a `PreToolUse(Bash)` hook that inspects every `git commit` invocation and rejects subjects that won't pass your CI's commit-subject check — catching the mistake locally instead of bouncing through the forge.

The gate is **configurable**: it mirrors whatever your CI enforces, and falls back to Conventional Commits when nothing is configured.

## How the regex resolves

In precedence order (exactly as the hook implements it):

1. **`AIF_COMMIT_PREFIX_REGEX` env var** — highest precedence; overrides everything.
2. **`.aif/config.yml` → `org.commit_prefix_regex`** — the per-project setting. The value must be double-quoted or bare on a single line (the hook extracts it with `awk`, not a YAML parser). Unfilled `<placeholder>` values from the config template are ignored.
3. **Default** — Conventional Commits with optional scope and `!`, plus common machine-generated subjects:

```
^((feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([^)]+\))?!?:|Merge|Revert|Bump|build\(deps\))
```

Under the default, all of these pass: `feat: add X`, `fix(api): handle nil`, `refactor!: drop legacy path`, `chore: bump deps`, `Merge branch ...`, `Revert "..."`, `Bump version`, `build(deps): bump lodash`.

## What the hook inspects (and skips)

The hook only fires on Bash commands containing a `git commit`. It extracts the subject — the first non-empty line of the `-m`/`--message` argument, including the heredoc shape `git commit -m "$(cat <<'EOF' ... EOF)"` and combined short flags like `-am "..."` — and matches it against the resolved regex.

It deliberately **passes without checking** when:

- `CLAUDE_DISABLE_COMMIT_PREFIX_CHECK=1` is set (see bypass below)
- `jq` is missing (hooks fail open — they must never block Bash on tooling gaps; subject extraction via `python3` is similarly tolerant)
- The commit uses the editor flow (`git commit` with no `-m`) — the subject is decided in `$EDITOR`, so nothing to validate statically
- `--amend --no-edit` (keeps the existing subject)
- `-F`/`--file` or `-C`/`-c` (reuse-message flags — the message was validated upstream)
- The subject can't be extracted (malformed quoting, exotic invocation)

## On failure

The hook blocks the commit (exit 1) and prints the offending subject, the regex it failed, the resolution order above, and how to fix it: rewrite the subject, or set `org.commit_prefix_regex` in `.aif/config.yml` to mirror what your CI actually enforces.

## Bypass (one-off)

Rare; usually means you should rewrite the subject instead:

```bash
CLAUDE_DISABLE_COMMIT_PREFIX_CHECK=1 git commit -m "..."
```

## Mirroring your CI

If your org's CI enforces a commit-subject convention, keep this hook in sync with it — the CI config is the source of truth, and `org.commit_prefix_regex` should mirror it exactly. Two tips:

- Anchor with `^` and test against a known-good subject before committing the config change (`grep -E "$REGEX" <<< "feat: x"` style).
- If different repos enforce different conventions, set `org.commit_prefix_regex` per repo in each repo's `.aif/config.yml`; use `AIF_COMMIT_PREFIX_REGEX` only for temporary experiments.

If your CI has no such gate, the Conventional Commits default is a sensible house style on its own — or set a permissive regex to effectively disable the check.
