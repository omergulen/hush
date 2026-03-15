#!/usr/bin/env bash
# PreToolUse hook for Claude Code.
# Rewrites known-safe commands to run through compress.sh for token savings.
# Only auto-approves commands in the safe-list below.

set -euo pipefail

# Resolve script location: plugin root, same directory (standalone), or ../bin (repo)
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    SCRIPT_DIR="$CLAUDE_PLUGIN_ROOT/bin"
else
    SELF="$(readlink -f "$0" 2>/dev/null || python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$0")"
    SELF_DIR="$(cd "$(dirname "$SELF")" && pwd)"
    if [ -f "$SELF_DIR/compress.sh" ]; then
        SCRIPT_DIR="$SELF_DIR"
    else
        SCRIPT_DIR="$(cd "$SELF_DIR/../bin" && pwd 2>/dev/null || echo "$SELF_DIR")"
    fi
fi

COMPRESS="$SCRIPT_DIR/compress.sh"
[ -f "$COMPRESS" ] || exit 0

# Read hook input; exit gracefully if jq fails
INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0

[ -z "$CMD" ] && exit 0

# ─── Guards: don't rewrite commands that can't be safely wrapped ─────────
[[ "$CMD" == *"compress.sh"* ]] && exit 0
[[ "$CMD" == *"<"* ]] && exit 0
[[ "$CMD" == *$'\n'* ]] && exit 0
[[ "$CMD" == *"|"* ]] && exit 0
[[ "$CMD" == *";"* ]] && exit 0
[[ "$CMD" == *'$('* ]] && exit 0
[[ "$CMD" == *'`'* ]] && exit 0
[[ "$CMD" == *"&"* ]] && exit 0
[[ "$CMD" == *">"* ]] && exit 0
[[ "$CMD" == *"("* ]] && exit 0

# Bypass: let agents/users skip compression when full output is needed
[[ "$CMD" == *"TOKEN_SAVER_BYPASS=1"* ]] && exit 0

# Extract base command past env var prefixes (e.g., FOO=bar cmd args)
BASE_CMD="$CMD"
PREFIX=""
if [[ "$CMD" =~ ^([A-Z_]+=[^ ]+[[:space:]]+)+(.*) ]]; then
    # Save match before blocklist check (inner =~ clears BASH_REMATCH)
    saved_base="${BASH_REMATCH[2]}"
    # Block dangerous env var overrides (library injection, path hijacking)
    if [[ "$CMD" =~ (^|[[:space:]])(LD_PRELOAD|LD_LIBRARY_PATH|DYLD_[A-Z_]*|PATH|BASH_ENV|ENV|PROMPT_COMMAND)= ]]; then
        exit 0
    fi
    PREFIX="${CMD% ${saved_base}}"
    PREFIX="$PREFIX "
    BASE_CMD="$saved_base"
fi

FIRST_WORD=$(echo "$BASE_CMD" | awk '{print $1}')
REST=$(echo "$BASE_CMD" | cut -d' ' -f2-)
[ "$REST" = "$FIRST_WORD" ] && REST=""

# ─── Permission policy: only auto-approve + compress known-safe commands ──
case "$FIRST_WORD" in
    # Trivial commands — skip entirely (no compression needed)
    cd|echo|mkdir|touch|export|source|pwd|whoami|true|false)
        exit 0
        ;;
    # Read-only / safe commands — auto-approve + compress
    cat|df|du|file|find|git|grep|head|ls|ps|rg|stat|tail|tree|wc)
        ;;
    # Build tools — auto-approve + compress (local state only)
    bundle|cargo|cmake|dotnet|go|make|mix|npm|pnpm|swift|yarn)
        ;;
    # Test runners — auto-approve + compress
    npx|pytest|rspec)
        ;;
    # Linters — auto-approve + compress (read-only analysis)
    biome|eslint|golangci-lint|hadolint|markdownlint|mypy|prettier|ruff|shellcheck|tsc|yamllint)
        ;;
    # Package managers — auto-approve + compress
    brew|composer|pip|poetry|uv)
        ;;
    # Infra / cloud tools — auto-approve + compress
    aws|docker|gcloud|gh|helm|kubectl|terraform|tofu)
        ;;
    # Python — only auto-approve module invocations (not arbitrary -c code)
    python|python3)
        # Block python -c / python -m with no module (arbitrary code execution)
        case "$REST" in
            -c*) exit 0 ;;
        esac
        ;;
    # Everything else — normal Claude Code permission flow, no compression
    *)
        exit 0
        ;;
esac

# Build the rewritten command
if [ -n "$REST" ]; then
    REWRITTEN="${PREFIX}${COMPRESS} ${FIRST_WORD} ${REST}"
else
    REWRITTEN="${PREFIX}${COMPRESS} ${FIRST_WORD}"
fi

cat <<HOOKEOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "token-saver: ${FIRST_WORD} output compression",
    "updatedInput": {
      "command": $(echo "$REWRITTEN" | jq -Rs .)
    }
  }
}
HOOKEOF
