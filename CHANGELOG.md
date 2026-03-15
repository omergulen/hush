# Changelog

## 1.1.0 (2026-03-15)

### Features

- **Tee mode** — saves full uncompressed output to `/tmp/hush-last-fail.txt` on command failure; breadcrumb includes path for LLM recovery
- **Dedup** — collapses consecutive similar lines (build logs, downloads) by normalizing numbers/hashes
- **JSON schema detection** — auto-detects JSON output, shows shape with types and array lengths, adds jq query hints
- **Discover** — `hush discover` analyzes log for commands with low compression, suggests filter rules
- **CLI wrapper** — `hush` command with subcommands: stats, discover, filters (list/add/test), status, version, upgrade
- **Versioning** — `VERSION` file as single source of truth, `CHANGELOG.md`, `hush version`, `hush upgrade`

## 1.0.0 (2026-03-15)

Initial release.

### Features

- **Config-driven compression** — ~90 command patterns via declarative `filters.conf`
- **6 strategies** — strip_lines, success_summary, tail_only, head_tail, custom, passthrough
- **Safe-list security model** — only known-safe commands are auto-approved; dangerous commands go through normal permission flow
- **Metacharacter guards** — blocks compound commands (`&&`, `|`, `;`, `&`, `>`, `<`, `$()`, backticks)
- **Env var blocklist** — blocks `LD_PRELOAD`, `PATH`, `DYLD_*`, etc. injection
- **Bypass** — `HUSH_BYPASS=1 <cmd>` for full uncompressed output
- **Stats** — `hush stats today`, `hush stats week --by-command`
- **LLM skill** — teaches the LLM to follow breadcrumbs, use jq for JSON, target specific test failures
- **74 tests** — covers hook rewrites, guards, strategies, security regressions
- **Plugin support** — Claude Code and Cursor marketplace manifests
- **Standalone installer** — `./install.sh` with uninstall and status checks
