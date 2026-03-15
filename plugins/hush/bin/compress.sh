#!/usr/bin/env bash
# compress.sh — Config-driven output compression for LLM token savings.
#
# Reads filters.conf to decide how to compress each command's output.
# Strategies: strip_lines, success_summary, tail_only, head_tail, custom, passthrough
# Every trimmed output includes breadcrumbs so the LLM can drill down.
#
# Usage: compress.sh <command> [args...]

set -uo pipefail

SELF="$(readlink -f "$0" 2>/dev/null || python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$0")"
SCRIPT_DIR="$(cd "$(dirname "$SELF")" && pwd)"
FILTERS_CONF="$SCRIPT_DIR/filters.conf"
LOG_FILE="${HUSH_LOG:-$HOME/.claude/hush.log}"
TEE_FILE="${HUSH_TEE_FILE:-${TMPDIR:-/tmp}/hush-last-fail.txt}"
[ -f "$LOG_FILE" ] || { mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null; touch "$LOG_FILE" 2>/dev/null; }
chmod 600 "$LOG_FILE" 2>/dev/null

CMD="$1"
shift
ALL_ARGS="$*"

if [ -n "$ALL_ARGS" ]; then
    FULL_CMD="$CMD $ALL_ARGS"
else
    FULL_CMD="$CMD"
fi

# Sanitize for safe logging (strip tabs/newlines that could corrupt TSV)
FULL_CMD_LOG=$(printf '%s' "$FULL_CMD" | tr '\t\n' '  ')

# ─── tee mode: save full output on failure ───────────────────────────────────
tee_on_fail() {
    local output="$1" exit_code="$2"
    if [ "$exit_code" -ne 0 ] || [ "${HUSH_TEE:-}" = "always" ]; then
        printf '%s' "$output" > "$TEE_FILE" 2>/dev/null
        chmod 600 "$TEE_FILE" 2>/dev/null
    fi
}

# ─── dedup: collapse consecutive similar lines ──────────────────────────────
dedup_output() {
    awk '
    {
        # Normalize: strip numbers, hashes, UUIDs for comparison
        normalized = $0
        gsub(/[0-9a-f]{7,}/, "HASH", normalized)
        gsub(/[0-9]+(\.[0-9]+)*/, "N", normalized)
        gsub(/[[:space:]]+/, " ", normalized)

        if (normalized == prev_normalized && NR > 1) {
            count++
            last_line = $0
        } else {
            if (count > 2) {
                printf "  ... (%d similar lines collapsed)\n", count
                print last_line
            } else if (count == 2) {
                print last_line
            }
            print
            count = 1
            last_line = $0
            prev_normalized = normalized
        }
    }
    END {
        if (count > 2) {
            printf "  ... (%d similar lines collapsed)\n", count
            print last_line
        } else if (count == 2) {
            print last_line
        }
    }'
}

# ─── JSON schema: detect JSON and show shape instead of raw data ─────────────
try_json_schema() {
    local output="$1"
    local line_count="$2"

    # Only attempt if output looks like JSON and jq is available
    local first_char
    first_char=$(printf '%s' "$output" | head -c1)
    if [[ "$first_char" != "{" && "$first_char" != "[" ]]; then
        return 1
    fi
    command -v jq >/dev/null 2>&1 || return 1

    # Validate it's actual JSON
    printf '%s' "$output" | jq empty 2>/dev/null || return 1

    # Extract schema
    local schema
    schema=$(printf '%s' "$output" | jq -r '
        def schema:
            if type == "array" then
                if length == 0 then "[]"
                else "[\(length) items] \(.[0] | schema)"
                end
            elif type == "object" then
                "{ " + ([to_entries[] | .key + ": " + (.value | schema)] | join(", ")) + " }"
            else type
            end;
        schema
    ' 2>/dev/null) || return 1

    [ -z "$schema" ] && return 1

    echo "$schema"
    echo ""
    echo "[Compressed: ${line_count} lines of JSON]"
    echo "[Full output: ${FULL_CMD}]"
    echo "[Hint: ${FULL_CMD} | jq 'keys']"
    echo "[Hint: ${FULL_CMD} | jq '.[0]']"
    return 0
}

# ─── breadcrumb: always tell the LLM what was trimmed ───────────────────────
breadcrumb() {
    local trimmed="$1"
    local hint="${2:-}"
    [ "$trimmed" -le 0 ] 2>/dev/null && return
    echo ""
    echo "[Compressed: ${trimmed} lines trimmed]"
    echo "[Full output: ${FULL_CMD}]"
    [ -n "$hint" ] && echo "[Hint: ${hint}]"
    # Tee mode breadcrumb
    if [ -f "$TEE_FILE" ] && [ -s "$TEE_FILE" ]; then
        echo "[Full output saved: ${TEE_FILE}]"
    fi
}

# ─── strategies ─────────────────────────────────────────────────────────────

strategy_strip_lines() {
    local pattern="$1"
    shift
    local output exit_code
    output=$("$CMD" "$@" 2>&1)
    exit_code=$?
    track_original "${#output}"
    tee_on_fail "$output" "$exit_code"
    local before after
    before=$(echo "$output" | wc -l | tr -d ' ')
    local filtered
    filtered=$(echo "$output" | grep -v -E "$pattern")
    after=$(echo "$filtered" | wc -l | tr -d ' ')
    echo "$filtered"
    breadcrumb "$((before - after))" "progress/noise lines stripped"
    return "$exit_code"
}

strategy_success_summary() {
    local tail_n="$1"
    shift
    local output exit_code
    output=$("$CMD" "$@" 2>&1)
    exit_code=$?
    track_original "${#output}"
    tee_on_fail "$output" "$exit_code"
    local line_count
    line_count=$(echo "$output" | wc -l | tr -d ' ')

    if [ "$exit_code" -eq 0 ]; then
        if [ "$line_count" -le "$((tail_n + 10))" ]; then
            echo "$output"
        else
            echo "$output" | tail -"$tail_n"
            breadcrumb "$((line_count - tail_n))" "succeeded — re-run only if you need specific details"
        fi
    else
        if [ "$line_count" -le 150 ]; then
            echo "$output"
        else
            echo "$output" | head -15
            echo ""
            echo "... [trimmed] ..."
            echo ""
            echo "$output" | grep -E -A 5 -B 1 '(FAIL|FAILED|ERROR|error|Error|panicked|AssertionError|Exception|Traceback|warning|Warning)' 2>/dev/null | head -80
            echo ""
            echo "---"
            echo "$output" | tail -30
            breadcrumb "$((line_count - 125))" "showing errors — re-run specific failing test for full trace"
        fi
    fi
    return "$exit_code"
}

strategy_tail_only() {
    local n="$1"
    shift
    local output exit_code
    output=$("$CMD" "$@" 2>&1)
    exit_code=$?
    track_original "${#output}"
    tee_on_fail "$output" "$exit_code"
    local line_count
    line_count=$(echo "$output" | wc -l | tr -d ' ')

    if [ "$line_count" -le "$((n + 5))" ]; then
        echo "$output"
    else
        echo "$output" | tail -"$n"
        breadcrumb "$((line_count - n))"
    fi
    return "$exit_code"
}

strategy_head_tail() {
    local head_n="$1"
    local tail_n="$2"
    shift 2
    local output exit_code
    output=$("$CMD" "$@" 2>&1)
    exit_code=$?
    track_original "${#output}"
    tee_on_fail "$output" "$exit_code"
    local line_count
    line_count=$(echo "$output" | wc -l | tr -d ' ')
    local threshold=$((head_n + tail_n + 10))

    if [ "$line_count" -le "$threshold" ]; then
        echo "$output"
    else
        echo "$output" | head -"$head_n"
        echo ""
        echo "... [middle trimmed] ..."
        echo ""
        echo "$output" | tail -"$tail_n"
        breadcrumb "$((line_count - head_n - tail_n))"
    fi
    return "$exit_code"
}

# ─── custom handlers (the few that need special logic) ──────────────────────

custom_git_status() {
    shift  # drop "status"
    local original
    original=$(git status "$@" 2>&1)
    track_original "${#original}"
    git status --short "$@"
}

custom_git_log() {
    shift  # drop "log"
    if [[ "$*" == *"--format"* ]] || [[ "$*" == *"--pretty"* ]] || [[ "$*" == *"-p"* ]]; then
        git log "$@"
    else
        local original exit_code
        original=$(git log "$@" 2>&1)
        exit_code=$?
        track_original "${#original}"
        git log --oneline -20 "$@"
        local total
        total=$(git rev-list --count HEAD 2>/dev/null || echo "?")
        echo ""
        echo "[Showing 20 of ${total} commits]"
        echo "[Detail: git log -p <commit> | git show <commit>]"
        return "$exit_code"
    fi
}

custom_git_diff() {
    shift  # drop "diff"
    local output exit_code
    output=$(git diff "$@" 2>&1)
    exit_code=$?
    track_original "${#output}"
    local line_count
    line_count=$(echo "$output" | wc -l | tr -d ' ')
    if [ "$line_count" -le 150 ]; then
        echo "$output"
    else
        git diff --stat "$@"
        echo ""
        local file_count
        file_count=$(git diff --stat "$@" 2>/dev/null | tail -1 | grep -oE '[0-9]+ file' | grep -oE '[0-9]+' || echo "?")
        echo "[Full diff is ${line_count} lines across ${file_count} files]"
        echo "[Detail: git diff <specific-file>]"
    fi
    return "$exit_code"
}

# ─── config reader & dispatcher ─────────────────────────────────────────────

dispatch() {
    if [ ! -f "$FILTERS_CONF" ]; then
        "$CMD" "$@"
        return $?
    fi

    while IFS= read -r line; do
        # Skip comments and blank lines
        line="${line#"${line%%[![:space:]]*}"}"
        [ -z "$line" ] && continue
        [[ "$line" == \#* ]] && continue

        # Split on ' | ' (space-pipe-space) to preserve | in regex patterns
        pattern=$(echo "$line" | awk -F' +\\| +' '{print $1}')
        strategy=$(echo "$line" | awk -F' +\\| +' '{print $2}')
        args=$(echo "$line" | awk -F' +\\| +' '{print $3}')

        # Trim whitespace with pure bash (no xargs — xargs mangles \b \s \d)
        pattern="${pattern#"${pattern%%[![:space:]]*}"}"
        pattern="${pattern%"${pattern##*[![:space:]]}"}"
        strategy="${strategy#"${strategy%%[![:space:]]*}"}"
        strategy="${strategy%"${strategy##*[![:space:]]}"}"
        args="${args#"${args%%[![:space:]]*}"}"
        args="${args%"${args##*[![:space:]]}"}"

        [ -z "$pattern" ] && continue

        if echo "$FULL_CMD" | grep -qE "$pattern" 2>/dev/null; then
            case "$strategy" in
                strip_lines)
                    strategy_strip_lines "$args" "$@"
                    return $?
                    ;;
                success_summary)
                    strategy_success_summary "$args" "$@"
                    return $?
                    ;;
                tail_only)
                    strategy_tail_only "$args" "$@"
                    return $?
                    ;;
                head_tail)
                    local h t
                    h=$(echo "$args" | awk '{print $1}')
                    t=$(echo "$args" | awk '{print $2}')
                    strategy_head_tail "$h" "$t" "$@"
                    return $?
                    ;;
                custom)
                    case "$args" in
                        git_status) custom_git_status "$@" ;;
                        git_log)    custom_git_log "$@" ;;
                        git_diff)   custom_git_diff "$@" ;;
                        *)
                            echo "Unknown custom handler: $args" >&2
                            "$CMD" "$@"
                            ;;
                    esac
                    return $?
                    ;;
                passthrough)
                    "$CMD" "$@"
                    return $?
                    ;;
                *)
                    "$CMD" "$@"
                    return $?
                    ;;
            esac
        fi
    done < "$FILTERS_CONF"

    # No matching rule — try JSON schema, then generic head/tail, passthrough for small
    local output exit_code
    output=$("$CMD" "$@" 2>&1)
    exit_code=$?
    track_original "${#output}"
    tee_on_fail "$output" "$exit_code"
    local line_count
    line_count=$(echo "$output" | wc -l | tr -d ' ')

    if [ "$line_count" -le 100 ]; then
        echo "$output"
    elif [ "$line_count" -gt 50 ] && try_json_schema "$output" "$line_count" 2>/dev/null; then
        # JSON schema handler succeeded — output already printed
        :
    else
        # Apply dedup then head/tail
        local deduped deduped_count
        deduped=$(echo "$output" | dedup_output)
        deduped_count=$(echo "$deduped" | wc -l | tr -d ' ')
        if [ "$deduped_count" -lt "$((line_count - 10))" ]; then
            # Dedup was effective — show deduped output (may still need head/tail)
            if [ "$deduped_count" -le 100 ]; then
                echo "$deduped"
                breadcrumb "$((line_count - deduped_count))" "similar lines collapsed"
            else
                echo "$deduped" | head -60
                echo ""
                echo "... [middle trimmed] ..."
                echo ""
                echo "$deduped" | tail -20
                breadcrumb "$((line_count - 80))" "similar lines collapsed + trimmed"
            fi
        else
            # No significant dedup — plain head/tail
            echo "$output" | head -60
            echo ""
            echo "... [middle trimmed] ..."
            echo ""
            echo "$output" | tail -20
            breadcrumb "$((line_count - 80))"
        fi
    fi
    return "$exit_code"
}

# ─── tracking ───────────────────────────────────────────────────────────────

TRACK_FILE=$(mktemp "${TMPDIR:-/tmp}/hush.XXXXXX" 2>/dev/null || echo "")
trap 'rm -f "$TRACK_FILE"' EXIT

track_original() {
    [ -n "$TRACK_FILE" ] && echo "$1" > "$TRACK_FILE"
}

log_savings() {
    local original_chars="$1" compressed_chars="$2" cmd="$3"
    local saved=$((original_chars - compressed_chars))
    local saved_tokens=$(( (saved + 3) / 4 ))
    local pct=0
    [ "$original_chars" -gt 0 ] && pct=$(( saved * 100 / original_chars ))
    printf '%s\t%s\t%d\t%d\t%d\t%d\t%d\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        "$cmd" \
        "$original_chars" \
        "$compressed_chars" \
        "$saved" \
        "$saved_tokens" \
        "$pct" \
        >> "$LOG_FILE" 2>/dev/null
}

compressed_output=$(dispatch "$@")
dispatch_exit=$?

printf '%s' "$compressed_output"
[ -n "$compressed_output" ] && [ "${compressed_output: -1}" != $'\n' ] && echo

if [ -n "$TRACK_FILE" ] && [ -f "$TRACK_FILE" ]; then
    original_chars=$(cat "$TRACK_FILE" 2>/dev/null || echo "0")
    compressed_chars=${#compressed_output}
    saved=$((original_chars - compressed_chars))
    if [ "$saved" -gt 100 ] && [ "$original_chars" -gt 0 ]; then
        pct=$(( saved * 100 / original_chars ))
        if [ "$pct" -gt 5 ]; then
            log_savings "$original_chars" "$compressed_chars" "$FULL_CMD_LOG"
        fi
    fi
fi

exit "$dispatch_exit"
