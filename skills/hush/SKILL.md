---
name: hush
description: >-
  View token savings stats or add new compression filters.
  Use when the user asks about token savings, compression stats, or wants to add a filter.
---

# Hush

Manage the hush output compression system.

## Stats

View token savings:

```bash
# All time
~/.hush/stats.sh all

# Today only
~/.hush/stats.sh today

# Last 7 days, broken down by command
~/.hush/stats.sh week --by-command
```

## Add a filter

To compress a new command, append one line to `~/.hush/filters.conf`:

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

## How compressed output works

When output is trimmed, the LLM sees breadcrumbs:

```
[Compressed: 340 lines trimmed]
[Full output: git diff]
[Hint: git diff <specific-file> for the file you need]
```

Follow the `[Hint:]` to drill down — don't re-run the full command.

## Bypass compression

When full uncompressed output is needed, prefix the command:

```bash
HUSH_BYPASS=1 git diff
```

Use sparingly — only when compressed output is insufficient.
