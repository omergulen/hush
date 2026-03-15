#!/usr/bin/env bash
# install.sh — One-command install for hush.
#
# Usage:
#   ./install.sh              Install for Claude Code
#   ./install.sh --uninstall  Remove everything
#   ./install.sh --status     Check installation
#
# What it does:
#   1. Copies bin/ scripts to ~/.hush/
#   2. Symlinks hook into ~/.claude/hooks/
#   3. Patches ~/.claude/settings.json with the PreToolUse hook
#   4. Installs the LLM instruction rule for Claude Code and Cursor

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.hush"
CLAUDE_HOOKS="$HOME/.claude/hooks"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"

# ─── Colors ─────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}+${NC} $1"; }
skip() { echo -e "  ${YELLOW}-${NC} $1"; }
fail() { echo -e "  ${RED}!${NC} $1"; }

# ─── Uninstall ──────────────────────────────────────────────────────────────
if [ "${1:-}" = "--uninstall" ]; then
    echo "Uninstalling hush..."

    rm -rf "$INSTALL_DIR" && ok "Removed $INSTALL_DIR" || skip "Not found: $INSTALL_DIR"
    rm -f "$CLAUDE_HOOKS/hush-hook.sh" "$CLAUDE_HOOKS/compress.sh" "$CLAUDE_HOOKS/filters.conf"
    ok "Removed hook symlinks"

    if [ -f "$CLAUDE_SETTINGS" ] && grep -q "hush-hook" "$CLAUDE_SETTINGS" 2>/dev/null; then
        jq '.hooks.PreToolUse = [.hooks.PreToolUse[] | select(.hooks[0].command | contains("hush") | not)]' \
            "$CLAUDE_SETTINGS" > "${CLAUDE_SETTINGS}.tmp" && mv "${CLAUDE_SETTINGS}.tmp" "$CLAUDE_SETTINGS"
        ok "Removed hook from settings.json"
    fi

    if [ -f "$CLAUDE_MD" ]; then
        grep -v '@HUSH.md' "$CLAUDE_MD" > "${CLAUDE_MD}.tmp" 2>/dev/null && mv "${CLAUDE_MD}.tmp" "$CLAUDE_MD"
    fi
    rm -f "$HOME/.claude/HUSH.md"
    ok "Removed LLM instruction"

    # Cursor rule (if installed)
    rm -f "$HOME/.cursor/rules/hush.mdc" 2>/dev/null

    echo ""
    echo "Done. Restart Claude Code for changes to take effect."
    exit 0
fi

# ─── Status ─────────────────────────────────────────────────────────────────
if [ "${1:-}" = "--status" ]; then
    echo "Hush Status"
    echo "══════════════════"

    [ -d "$INSTALL_DIR" ] && ok "Installed at $INSTALL_DIR" || fail "Not installed"
    [ -L "$CLAUDE_HOOKS/hush-hook.sh" ] && ok "Hook symlink exists" || fail "Hook symlink missing"

    if [ -f "$CLAUDE_SETTINGS" ] && grep -q "hush-hook" "$CLAUDE_SETTINGS" 2>/dev/null; then
        ok "Registered in settings.json"
    else
        fail "Not registered in settings.json"
    fi

    if [ -f "$HOME/.claude/hush.log" ]; then
        ENTRIES=$(wc -l < "$HOME/.claude/hush.log" | tr -d ' ')
        ok "Log has $ENTRIES entries"
    else
        skip "No log file yet (no compressions recorded)"
    fi

    exit 0
fi

# ─── Prereqs ────────────────────────────────────────────────────────────────
echo "Installing hush..."
echo ""

if ! command -v jq &>/dev/null; then
    fail "jq is required but not installed."
    echo "    Install: brew install jq  (macOS) or apt install jq (Linux)"
    exit 1
fi

# ─── Step 1: Copy scripts ──────────────────────────────────────────────────
echo "Scripts:"
mkdir -p "$INSTALL_DIR"
for file in compress.sh discover.sh filters.conf hush stats.sh; do
    cp "$REPO_DIR/plugins/hush/bin/$file" "$INSTALL_DIR/$file"
    ok "$INSTALL_DIR/$file"
done
cp "$REPO_DIR/plugins/hush/hooks/hook.sh" "$INSTALL_DIR/hook.sh"
ok "$INSTALL_DIR/hook.sh"
chmod +x "$INSTALL_DIR"/*.sh

# ─── Step 2: Hook symlinks ─────────────────────────────────────────────────
echo ""
echo "Claude Code hooks:"
mkdir -p "$CLAUDE_HOOKS"
for pair in "hook.sh:hush-hook.sh" "compress.sh:compress.sh" "filters.conf:filters.conf"; do
    src="$INSTALL_DIR/${pair%%:*}"
    target="$CLAUDE_HOOKS/${pair##*:}"
    if [ -L "$target" ] && [ "$(readlink "$target")" = "$src" ]; then
        skip "$(basename "$target") (already linked)"
    else
        ln -sf "$src" "$target"
        ok "$(basename "$target") -> $src"
    fi
done

# ─── Step 3: Patch settings.json ───────────────────────────────────────────
echo ""
echo "Settings:"
HOOK_CMD="$CLAUDE_HOOKS/hush-hook.sh"
HOOK_ENTRY='{"matcher":"Bash","hooks":[{"type":"command","command":"'"$HOOK_CMD"'"}]}'

if [ -f "$CLAUDE_SETTINGS" ] && grep -q "hush-hook" "$CLAUDE_SETTINGS" 2>/dev/null; then
    skip "Already registered in settings.json"
else
    if [ -f "$CLAUDE_SETTINGS" ]; then
        if jq -e '.hooks.PreToolUse' "$CLAUDE_SETTINGS" >/dev/null 2>&1; then
            jq --argjson entry "$HOOK_ENTRY" '.hooks.PreToolUse += [$entry]' "$CLAUDE_SETTINGS" > "${CLAUDE_SETTINGS}.tmp"
        else
            jq --argjson entry "$HOOK_ENTRY" '.hooks.PreToolUse = [$entry]' "$CLAUDE_SETTINGS" > "${CLAUDE_SETTINGS}.tmp"
        fi
        mv "${CLAUDE_SETTINGS}.tmp" "$CLAUDE_SETTINGS"
    else
        mkdir -p "$(dirname "$CLAUDE_SETTINGS")"
        echo "{\"hooks\":{\"PreToolUse\":[$HOOK_ENTRY]}}" | jq . > "$CLAUDE_SETTINGS"
    fi
    ok "Registered hook in settings.json"
fi

# ─── Step 4: LLM instruction ───────────────────────────────────────────────
echo ""
echo "LLM instruction:"
cp "$REPO_DIR/plugins/hush/rules/hush-instruction.md" "$HOME/.claude/HUSH.md"
ok "Installed HUSH.md"

if [ -f "$CLAUDE_MD" ]; then
    if ! grep -q '@HUSH.md' "$CLAUDE_MD" 2>/dev/null; then
        echo "" >> "$CLAUDE_MD"
        echo "@HUSH.md" >> "$CLAUDE_MD"
        ok "Added @HUSH.md reference to CLAUDE.md"
    else
        skip "@HUSH.md already in CLAUDE.md"
    fi
else
    echo "@HUSH.md" > "$CLAUDE_MD"
    ok "Created CLAUDE.md with @HUSH.md"
fi

# ─── Step 5 (optional): Cursor rule ────────────────────────────────────────
if [ -d "$HOME/.cursor/rules" ]; then
    echo ""
    echo "Cursor:"
    cp "$REPO_DIR/plugins/hush/rules/hush.mdc" "$HOME/.cursor/rules/hush.mdc"
    ok "Installed hush.mdc rule"
fi

# ─── Done ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}Done!${NC} Restart Claude Code for the hook to take effect."
echo ""
echo "Commands:"
echo "  $INSTALL_DIR/stats.sh today          View today's savings"
echo "  $INSTALL_DIR/stats.sh week --by-command  Weekly breakdown"
echo "  ./install.sh --status                Check installation"
echo "  ./install.sh --uninstall             Remove everything"
