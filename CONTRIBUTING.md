# Contributing to Hush

## Quick start

```bash
git clone https://github.com/omergulen/hush.git
cd hush
./test/run_tests.sh  # 74 tests, should all pass
```

## Adding a compression filter

Add one line to `plugins/hush/bin/filters.conf`:

```
^my-command\b    | success_summary | 10
```

See the [README](README.md#adding-filters) for available strategies.

## Running tests

```bash
./test/run_tests.sh
```

Tests cover hook rewrites, metacharacter guards, permission policy, strategy dispatch, exit code preservation, security regressions, tee mode, dedup, JSON schema, and CLI commands. Add tests for any new behavior.

## Code style

- Bash only — no compiled dependencies
- `set -euo pipefail` in hook scripts, `set -uo pipefail` in compress.sh (intentionally no `-e`)
- Pure bash for string manipulation (no `xargs` — it mangles backslash sequences)
- Comments for non-obvious logic

## Security

- Never auto-approve destructive commands — add to the safe-list in `hooks/hook.sh` only if the command is read-only or modifies only local state
- Test metacharacter guards when adding new shell features
- Report vulnerabilities via GitHub issues

## Releasing a new version

Follow these steps to ship a new version:

### 1. Bump the version

```bash
# Edit the VERSION file (single source of truth)
echo "1.2.0" > VERSION
```

### 2. Update all manifests

Version must match in all these files:

| File | Field |
|------|-------|
| `VERSION` | entire file |
| `.claude-plugin/marketplace.json` | `version` + `plugins[0].version` |
| `.cursor-plugin/marketplace.json` | `metadata.version` |
| `plugins/hush/.claude-plugin/plugin.json` | `version` |
| `plugins/hush/.cursor-plugin/plugin.json` | `version` |

### 3. Update CHANGELOG.md

Add a new section at the top:

```markdown
## X.Y.Z (YYYY-MM-DD)

### Features
- **Feature name** — what it does

### Fixes
- **Fix description** — what was broken
```

### 4. Commit, tag, and push

```bash
git add VERSION CHANGELOG.md .claude-plugin/ .cursor-plugin/ plugins/hush/.claude-plugin/ plugins/hush/.cursor-plugin/
git commit -m "Release vX.Y.Z"
git tag -a vX.Y.Z -m "hush vX.Y.Z — short description"
git push origin main --tags
```

### 5. Create GitHub release (optional)

```bash
gh release create vX.Y.Z --title "hush vX.Y.Z" --notes-file CHANGELOG.md
```

### Versioning policy

- **Major** (2.0.0) — breaking changes to hook behavior, config format, or CLI commands
- **Minor** (1.1.0) — new features, new strategies, new CLI subcommands
- **Patch** (1.1.1) — bug fixes, filter additions, documentation updates
