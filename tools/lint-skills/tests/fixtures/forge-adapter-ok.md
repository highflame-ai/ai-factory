# Fixture: adapter usage + exempt gh ops — no findings expected (REQ-520 BR-1)

PR ops route through the adapter, and the two exempt direct ops (`gh pr diff`,
`gh pr checks`) are allowed.

```sh
. .aif/partials/forge.sh 2>/dev/null || . ~/.claude/skills/partials/forge.sh
aif_forge_pr_merge "$prUrl" --squash --delete-branch
aif_forge_pr_view "$prUrl" --fields state,url
```

```sh
gh pr diff "$prUrl"
gh pr checks "$prUrl"
```

No `forge-direct-gh` finding expected.
