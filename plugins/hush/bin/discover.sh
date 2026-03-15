#!/usr/bin/env bash
# discover.sh — Find commands that would benefit from compression filters.
# Analyzes hush.log for commands with low compression or high output.
#
# Usage: discover.sh [--min-runs N] [--min-tokens N]

set -euo pipefail

LOG_FILE="${HUSH_LOG:-$HOME/.claude/hush.log}"

if [ ! -f "$LOG_FILE" ]; then
    echo "No log file found at $LOG_FILE"
    echo "Run some commands first so hush can collect data."
    exit 0
fi

MIN_RUNS="${1:-3}"
MIN_TOKENS="${2:-100}"

echo "Hush — Optimization Opportunities"
echo "═══════════════════════════════════════"
echo "Commands with low compression (candidates for custom filters):"
echo ""

# TSV: timestamp, command, original_chars, compressed_chars, saved_chars, saved_tokens, pct
# Find commands with low compression % or high original output
awk -F'\t' -v min_runs="$MIN_RUNS" -v min_tokens="$MIN_TOKENS" '
{
    # Extract base command (first 2 words)
    split($2, parts, " ")
    if (parts[2] != "") cmd = parts[1] " " parts[2]
    else cmd = parts[1]

    count[cmd]++
    orig[cmd] += $3
    saved[cmd] += $5
    tokens_saved[cmd] += $6
}
END {
    found = 0
    # Sort by potential savings (original - saved = wasted tokens)
    for (cmd in count) {
        if (count[cmd] < min_runs) continue
        pct = (orig[cmd] > 0) ? int(saved[cmd] * 100 / orig[cmd]) : 0
        wasted = int((orig[cmd] - saved[cmd]) / 4)  # chars to tokens
        if (wasted < min_tokens) continue

        # Suggest a strategy based on command name
        suggestion = "head_tail | 40 10"
        if (cmd ~ /test|spec|check/) suggestion = "success_summary | 15"
        if (cmd ~ /build|install|compile/) suggestion = "strip_lines | ^\\s*(Compiling|Building|Installing)"
        if (cmd ~ /log|tail/) suggestion = "tail_only | 30"

        printf "  %-35s %4d runs   ~%d tokens could be saved\n", cmd, count[cmd], wasted
        printf "    Suggested: ^%s | %s\n\n", cmd, suggestion
        found++
    }
    if (found == 0) {
        print "  No optimization opportunities found."
        print "  All frequently-run commands have good compression ratios."
    }
}' "$LOG_FILE"
