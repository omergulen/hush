#!/usr/bin/env bash
# stats.sh — Token saver savings report.
# Reads ~/.claude/token-saver.log and shows a summary.
#
# Usage: stats.sh [today|week|all] [--by-command]

set -euo pipefail

LOG_FILE="${TOKEN_SAVER_LOG:-$HOME/.claude/token-saver.log}"

if [ ! -f "$LOG_FILE" ]; then
    echo "No log file found at $LOG_FILE"
    echo "Token saver hasn't compressed anything yet."
    exit 0
fi

PERIOD="${1:-all}"
BY_CMD="${2:-}"

# Filter by period
case "$PERIOD" in
    today)
        TODAY=$(date -u +%Y-%m-%d)
        DATA=$(grep "^$TODAY" "$LOG_FILE" || true)
        LABEL="Today"
        ;;
    week)
        # Last 7 days
        if date -v-7d +%Y-%m-%d >/dev/null 2>&1; then
            WEEK_AGO=$(date -v-7d -u +%Y-%m-%d)
        else
            WEEK_AGO=$(date -u -d '7 days ago' +%Y-%m-%d 2>/dev/null || date -u +%Y-%m-%d)
        fi
        DATA=$(awk -F'\t' -v since="$WEEK_AGO" '$1 >= since' "$LOG_FILE" || true)
        LABEL="Last 7 days"
        ;;
    all)
        DATA=$(cat "$LOG_FILE")
        LABEL="All time"
        ;;
    *)
        echo "Usage: stats.sh [today|week|all] [--by-command]"
        exit 1
        ;;
esac

if [ -z "$DATA" ]; then
    echo "$LABEL: no compressions recorded."
    exit 0
fi

# Calculate totals
# TSV: timestamp, command, original_chars, compressed_chars, saved_chars, saved_tokens, pct
TOTAL_ORIGINAL=$(echo "$DATA" | awk -F'\t' '{sum+=$3} END {print sum+0}')
TOTAL_COMPRESSED=$(echo "$DATA" | awk -F'\t' '{sum+=$4} END {print sum+0}')
TOTAL_SAVED=$(echo "$DATA" | awk -F'\t' '{sum+=$5} END {print sum+0}')
TOTAL_TOKENS_SAVED=$(echo "$DATA" | awk -F'\t' '{sum+=$6} END {print sum+0}')
TOTAL_INVOCATIONS=$(echo "$DATA" | wc -l | tr -d ' ')
AVG_PCT=0
[ "$TOTAL_ORIGINAL" -gt 0 ] && AVG_PCT=$(( TOTAL_SAVED * 100 / TOTAL_ORIGINAL ))

# Format large numbers with commas
fmt() {
    printf "%'d" "$1" 2>/dev/null || printf "%d" "$1"
}

echo "Token Saver — $LABEL"
echo "═══════════════════════════════════════"
echo "  Invocations:       $(fmt "$TOTAL_INVOCATIONS")"
echo "  Original output:   $(fmt "$TOTAL_ORIGINAL") chars (~$(fmt $(( (TOTAL_ORIGINAL + 3) / 4 ))) tokens)"
echo "  Compressed output: $(fmt "$TOTAL_COMPRESSED") chars (~$(fmt $(( (TOTAL_COMPRESSED + 3) / 4 ))) tokens)"
echo "  Saved:             $(fmt "$TOTAL_SAVED") chars (~$(fmt "$TOTAL_TOKENS_SAVED") tokens)"
echo "  Compression:       ${AVG_PCT}%"

if [ "$BY_CMD" = "--by-command" ]; then
    echo ""
    echo "By command (top 15):"
    echo "───────────────────────────────────────"
    printf "  %-30s %8s %10s %5s\n" "COMMAND" "COUNT" "TOKENS SAVED" "AVG%"
    echo "$DATA" | awk -F'\t' '{
        # Extract base command (first 2 words)
        split($2, parts, " ")
        if (parts[2] != "") cmd = parts[1] " " parts[2]
        else cmd = parts[1]
        count[cmd]++
        saved[cmd]+=$6
        orig[cmd]+=$3
    } END {
        for (cmd in count) {
            pct = (orig[cmd] > 0) ? int(saved[cmd] * 4 * 100 / orig[cmd]) : 0
            printf "  %-30s %8d %10d %4d%%\n", cmd, count[cmd], saved[cmd], pct
        }
    }' | sort -t$'\t' -k3 -rn | head -15
fi

echo ""
echo "Log: $LOG_FILE ($(wc -l < "$LOG_FILE" | tr -d ' ') entries)"
