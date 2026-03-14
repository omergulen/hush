#!/usr/bin/env bash
# PreToolUse hook for Claude Code.
# Rewrites known-verbose commands to run through compress.sh.
# Auto-approves ONLY the rewritten commands (safe because compress.sh is yours).
#
# Installed via symlink: ~/.claude/hooks/token-saver-hook.sh → this file

set -euo pipefail

# Resolve symlinks to find the actual script dir (where compress.sh lives)
SELF="$(readlink -f "$0" 2>/dev/null || python3 -c "import os; print(os.path.realpath('$0'))")"
SCRIPT_DIR="$(cd "$(dirname "$SELF")" && pwd)"
COMPRESS="$SCRIPT_DIR/compress.sh"

# Bail if compress.sh is missing
[ -f "$COMPRESS" ] || exit 0

# Read hook input
INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[ -z "$CMD" ] && exit 0

# Don't rewrite commands that are already wrapped
[[ "$CMD" == *"compress.sh"* ]] && exit 0

# Don't rewrite heredocs, multi-line, or piped commands — too complex
[[ "$CMD" == *"<<"* ]] && exit 0
[[ "$CMD" == *$'\n'* ]] && exit 0
[[ "$CMD" == *"|"* ]] && exit 0

# Extract the base command (handle env var prefixes like FOO=bar cmd)
BASE_CMD="$CMD"
PREFIX=""
if [[ "$CMD" =~ ^([A-Z_]+=[^ ]+[[:space:]]+)+(.*) ]]; then
    PREFIX="${CMD% ${BASH_REMATCH[2]}}"
    PREFIX="$PREFIX "
    BASE_CMD="${BASH_REMATCH[2]}"
fi

# Get the first word (the actual command)
FIRST_WORD=$(echo "$BASE_CMD" | awk '{print $1}')
REST=$(echo "$BASE_CMD" | cut -d' ' -f2-)
[ "$REST" = "$FIRST_WORD" ] && REST=""

# Commands we have specific compression for.
# Everything else hits the generic trimmer (still useful for huge output).
case "$FIRST_WORD" in
    git|ls|grep|rg|cat|pytest|cargo|npm|yarn|pnpm|make|cmake)
        ;;
    python|python3)
        ;;
    gh|docker|kubectl|terraform|tofu|ansible-playbook|aws|gcloud)
        ;;
    go|dotnet|swift|mix)
        ;;
    eslint|tsc|ruff|mypy|prettier|biome|shellcheck|hadolint|golangci-lint)
        ;;
    curl|wget|rsync|ping|find|tree|ps|df|du|brew|pip|uv|poetry)
        ;;
    npx)
        ;;
    # Simple commands that never produce large output — skip
    cd|echo|mkdir|rm|cp|mv|chmod|chown|touch|export|source|which|type|pwd|whoami|true|false)
        exit 0
        ;;
    *)
        # Unknown command — still route through generic trimmer for huge output
        ;;
esac

# Build the rewritten command
if [ -n "$REST" ]; then
    REWRITTEN="${PREFIX}${COMPRESS} ${FIRST_WORD} ${REST}"
else
    REWRITTEN="${PREFIX}${COMPRESS} ${FIRST_WORD}"
fi

# Return the rewrite with auto-allow.
# Safe because compress.sh is YOUR code — no third-party binary.
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
