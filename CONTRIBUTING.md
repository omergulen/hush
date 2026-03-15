# Contributing to Hush

## Quick start

```bash
git clone https://github.com/omergulen/hush.git
cd hush
./test/run_tests.sh  # 61 tests, should all pass
```

## Adding a compression filter

Add one line to `bin/filters.conf`:

```
^my-command\b    | success_summary | 10
```

See the [README](README.md#adding-filters) for available strategies.

## Running tests

```bash
./test/run_tests.sh
```

Tests cover hook rewrites, metacharacter guards, permission policy, strategy dispatch, exit code preservation, and security regressions. Add tests for any new behavior.

## Code style

- Bash only — no compiled dependencies
- `set -euo pipefail` in hook scripts, `set -uo pipefail` in compress.sh (intentionally no `-e`)
- Pure bash for string manipulation (no `xargs` — it mangles backslash sequences)
- Comments for non-obvious logic

## Security

- Never auto-approve destructive commands — add to the safe-list in `hooks/hook.sh` only if the command is read-only or modifies only local state
- Test metacharacter guards when adding new shell features
- Report vulnerabilities via GitHub issues
