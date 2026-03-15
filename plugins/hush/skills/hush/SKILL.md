---
name: hush
description: >-
  Manage hush output compression — view stats, discover optimization opportunities, add filters, check failures.
  Use when the user asks about token savings, compression stats, or wants to add a filter.
---

# Hush

Manage the hush output compression system.

## CLI

Hush provides a single CLI entry point. Find it with:

```bash
# Plugin install
$(find ~/.claude/plugins/cache/hush -name "hush" -type f 2>/dev/null | head -1) help

# Standalone install
~/.hush/hush help
```

Available commands:

```bash
hush stats [today|week|all] [--by-command]   # View token savings
hush discover                                 # Find optimization opportunities
hush filters list                             # Show active rules
hush filters add <pattern> <strategy> [args]  # Add a new rule
hush filters test <command>                   # Test which rule matches a command
hush status                                   # Installation health check
```

## Working with compressed output

When output is trimmed, you'll see breadcrumbs:

```
[Compressed: 340 lines trimmed]
[Full output: git diff]
[Hint: git diff <specific-file> for the file you need]
```

Follow the `[Hint:]` to drill down — don't re-run the full command.

## Failed command output

When a command fails and its output is compressed, the full uncompressed output is saved:

```
[Full output saved: /tmp/hush-last-fail.txt]
```

Read the saved file instead of re-running the failed command:

```bash
cat /tmp/hush-last-fail.txt | head -100
cat /tmp/hush-last-fail.txt | grep -E 'ERROR|FAIL'
```

## Working with JSON output

When a command returns large JSON, hush shows the schema automatically. To query specific paths:

```bash
# Inspect structure
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

Hush automatically collapses consecutive similar lines (build logs, downloads, etc.). When you see `(N similar lines collapsed)`, the repeated content was noise — focus on the unique lines around it.

## Working with test failures

When a test run is compressed, only failing tests are shown. To get the full trace of a specific failure:

```bash
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

If a command consistently produces large uncompressed output, suggest adding a filter:

```bash
hush filters add '^my-command\b' success_summary 10
```

Available strategies:
- `strip_lines <regex>` — remove lines matching regex
- `success_summary <N>` — on exit 0: last N lines. on failure: show all
- `tail_only <N>` — always show last N lines
- `head_tail <H> <T>` — first H + last T lines
- `passthrough` — no compression
