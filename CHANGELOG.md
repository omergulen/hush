# Changelog

## 1.0.0 (2026-03-15)

Initial release.

### Features

- **Config-driven compression** — ~90 command patterns via declarative `filters.conf`
- **6 strategies** — strip_lines, success_summary, tail_only, head_tail, custom, passthrough
- **Safe-list security model** — only known-safe commands are auto-approved; dangerous commands go through normal permission flow
- **Metacharacter guards** — blocks compound commands (`&&`, `|`, `;`, `&`, `>`, `<`, `$()`, backticks)
- **Env var blocklist** — blocks `LD_PRELOAD`, `PATH`, `DYLD_*`, etc. injection
- **Tee mode** — saves full uncompressed output on failure to `/tmp/hush-last-fail.txt`
- **Dedup** — collapses consecutive similar lines (build logs, downloads)
- **JSON schema detection** — auto-detects JSON, shows shape + jq query hints
- **Bypass** — `HUSH_BYPASS=1 <cmd>` for full uncompressed output
- **Stats** — `hush stats today`, `hush stats week --by-command`
- **Discover** — `hush discover` finds commands that would benefit from custom filters
- **CLI wrapper** — `hush` command with stats, discover, filters, status subcommands
- **LLM skill** — teaches the LLM to follow breadcrumbs, use jq for JSON, target specific test failures
- **73 tests** — covers hook rewrites, guards, strategies, security regressions, all new features
- **Plugin support** — Claude Code and Cursor marketplace manifests
- **Standalone installer** — `./install.sh` with uninstall and status checks
