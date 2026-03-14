#!/usr/bin/env bash
# PreToolUse hook for Claude Code plugin.
# Rewrites commands to run through compress.sh for token savings.

set -euo pipefail

# Resolve script location: plugin root or symlink target
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    SCRIPT_DIR="$CLAUDE_PLUGIN_ROOT/bin"
else
    SELF="$(readlink -f "$0" 2>/dev/null || python3 -c "import os; print(os.path.realpath('$0'))")"
    SCRIPT_DIR="$(cd "$(dirname "$SELF")/../bin" && pwd)"
fi

COMPRESS="$SCRIPT_DIR/compress.sh"
[ -f "$COMPRESS" ] || exit 0

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[ -z "$CMD" ] && exit 0

# Don't rewrite already-wrapped, heredocs, multi-line, or piped commands
[[ "$CMD" == *"compress.sh"* ]] && exit 0
[[ "$CMD" == *"<<"* ]] && exit 0
[[ "$CMD" == *$'\n'* ]] && exit 0
[[ "$CMD" == *"|"* ]] && exit 0

# Extract base command past env var prefixes
BASE_CMD="$CMD"
PREFIX=""
if [[ "$CMD" =~ ^([A-Z_]+=[^ ]+[[:space:]]+)+(.*) ]]; then
    PREFIX="${CMD% ${BASH_REMATCH[2]}}"
    PREFIX="$PREFIX "
    BASE_CMD="${BASH_REMATCH[2]}"
fi

FIRST_WORD=$(echo "$BASE_CMD" | awk '{print $1}')
REST=$(echo "$BASE_CMD" | cut -d' ' -f2-)
[ "$REST" = "$FIRST_WORD" ] && REST=""

# Simple commands that never produce large output — skip
case "$FIRST_WORD" in
    cd|echo|mkdir|rm|cp|mv|chmod|chown|touch|export|source|which|type|pwd|whoami|true|false)
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
