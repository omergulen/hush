# token-saver

Compresses CLI output to save LLM context window tokens. Zero dependencies beyond bash and jq.

Works as a **Claude Code plugin**, **Cursor plugin**, or **standalone install**. Intercepts verbose commands and returns compressed output with breadcrumbs so the LLM can drill down when needed.

## Install

### Claude Code (plugin)

```
/install-plugin <org>/token-saver
```

### Cursor (plugin)

```
/add-plugin <org>/token-saver
```

### Standalone (no plugin system)

```bash
git clone <this-repo>
cd token-saver
./install.sh
```

Restart your editor after installing.

## How it works

```
$ git diff
 src/auth.ts   | 45 +++++++++
 src/config.ts |  3 +-
 2 files changed, 46 insertions(+), 2 deletions(-)

[Full diff is 890 lines across 2 files]
[Detail: git diff <specific-file>]
```

1. A PreToolUse hook intercepts Bash commands
2. Commands route through `compress.sh` which applies per-command strategies
3. The LLM sees compressed output with breadcrumbs showing what was trimmed
4. When the LLM needs detail, it follows the breadcrumb — not the full re-run

## What it compresses

~90 commands via declarative rules in [`bin/filters.conf`](bin/filters.conf):

| Category | Examples | Strategy |
|----------|----------|----------|
| Git | status, push, pull, fetch, clone, log, diff | Short format, strip progress |
| Test runners | pytest, jest, vitest, cargo test, go test, rspec... | Passing: summary. Failing: full |
| Build tools | cargo build, npm install, make, xcodebuild, mvn... | Strip compilation noise |
| Linters | eslint, tsc, ruff, mypy, clippy, shellcheck... | Head + tail |
| Docker/K8s | build, logs, ps, kubectl... | Strip layer progress, tail logs |
| Cloud/Infra | terraform, aws, gcloud, ansible... | Head + tail |
| Package managers | npm, pip, poetry, brew, composer... | Summary on success |
| File tools | find, grep, cat, ls, tree | Head + tail |

Adding a command is one line in `filters.conf`.

## Adding filters

```
# Format: PATTERN | STRATEGY | ARGS
^my-command\b    | success_summary | 10
```

Strategies:
- `strip_lines <regex>` — remove matching lines
- `success_summary <N>` — on success: last N lines. on failure: full output
- `tail_only <N>` — always last N lines
- `head_tail <H> <T>` — first H + last T lines
- `passthrough` — no compression
- `custom <handler>` — custom bash function

## Stats

```bash
~/.token-saver/stats.sh today
~/.token-saver/stats.sh week --by-command
```

```
Token Saver — Last 7 days
═══════════════════════════════════════
  Invocations:       142
  Original output:   1,284,000 chars (~321,000 tokens)
  Compressed output: 189,000 chars (~47,250 tokens)
  Saved:             1,095,000 chars (~273,750 tokens)
  Compression:       85%
```

## Why not rtk?

[rtk-ai/rtk](https://github.com/rtk-ai/rtk) does the same thing in Rust with ~120 commands. But:

- **Auto-approves commands** — bypasses Claude Code's permission system
- **Third-party binary** — supply chain risk if maintainers go malicious
- **Opt-out telemetry** — daily usage analytics
- **1.3M lines of Rust** — hard to audit

token-saver gives ~80% of the savings in ~750 lines of auditable bash. No binary, no telemetry, no supply chain.

## Architecture

```
token-saver/
├── bin/
│   ├── compress.sh    (310 lines)  Config-driven compression engine
│   ├── hook.sh        (92 lines)   Standalone hook (for manual install)
│   ├── filters.conf   (119 lines)  ~90 command patterns
│   └── stats.sh       (97 lines)   Savings reporting
├── hooks/
│   ├── hooks.json                   Claude Code plugin hook config
│   └── hook.sh                      Plugin-aware hook entry point
├── rules/
│   ├── token-saver.mdc              Cursor rule (LLM instruction)
│   └── token-saver-instruction.md   Claude Code rule (LLM instruction)
├── skills/
│   └── token-saver/SKILL.md         Stats & filter management skill
├── install.sh                        Standalone installer
└── README.md
```

## Uninstall

Plugin: `/remove-plugin token-saver`

Standalone: `./install.sh --uninstall`

## License

MIT
