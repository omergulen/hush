---
name: hush
description: >-
  View token savings stats or add new compression filters.
  Use when the user asks about token savings, compression stats, or wants to add a filter.
---

# Hush

Manage the hush output compression system.

## Working with compressed output

When output is trimmed, you'll see breadcrumbs:

```
[Compressed: 340 lines trimmed]
[Full output: git diff]
[Hint: git diff <specific-file> for the file you need]
```

Follow the `[Hint:]` to drill down — don't re-run the full command.

## Working with JSON output

When a command returns large JSON, don't re-fetch it all. Use `jq` to query specific paths:

```bash
# Inspect structure first
<cmd> | jq 'keys'
<cmd> | jq '.[0] | keys'
<cmd> | jq 'type, length'

# Extract specific fields
<cmd> | jq '.results[0].message'
<cmd> | jq '.items[] | {name, status}'

# Filter by condition
<cmd> | jq '.results[] | select(.status == "error")'

# Count items
<cmd> | jq '.results | length'
```

Always check the shape before requesting all the data.

## Working with repeated output

When output contains many similar lines (build logs, download progress, CI output), don't read every line. Check the pattern and the final result:

```bash
# Instead of reading 500 "Downloading..." lines:
<cmd> | tail -5

# Instead of reading 200 "Compiling..." lines:
<cmd> | grep -E '(error|warning|FAIL)'
```

## Working with test failures

When a test run is compressed, only failing tests are shown. To get the full trace of a specific failure:

```bash
# Re-run just the failing test
pytest tests/test_auth.py::test_login -v
cargo test auth::test_login -- --nocapture
npm test -- --testNamePattern "login"
```

Don't re-run the entire suite — target the specific failure.

## Bypass compression

When full uncompressed output is genuinely needed, prefix the command:

```bash
HUSH_BYPASS=1 git diff
```

Use sparingly — only when compressed output is insufficient.

## Suggesting new filters

If a command consistently produces large uncompressed output (no `[Compressed:]` breadcrumb despite long output), suggest adding a filter:

```
# Format: PATTERN | STRATEGY | ARGS
^my-command\b    | success_summary | 10
```

Available strategies:
- `strip_lines <regex>` — remove lines matching regex
- `success_summary <N>` — on exit 0: last N lines. on failure: show all
- `tail_only <N>` — always show last N lines
- `head_tail <H> <T>` — first H + last T lines
- `passthrough` — no compression

Append to `~/.hush/filters.conf` (standalone) or the plugin's `bin/filters.conf`.

## Stats

View token savings:

```bash
~/.hush/stats.sh all
~/.hush/stats.sh today
~/.hush/stats.sh week --by-command
```
