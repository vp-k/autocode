#!/usr/bin/env bash
# AutoCode dashboard.sh Unit Tests
# Usage: bash tests/test_dashboard.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DASHBOARD_SCRIPT="$PROJECT_DIR/scripts/dashboard.sh"
TEST_DIR=""
PASS=0
FAIL=0
TOTAL=0

# ─── Helpers ───
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$expected" == "$actual" ]]; then
        echo -e "${GREEN}PASS${NC} $desc"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}FAIL${NC} $desc"
        echo "  Expected: $expected"
        echo "  Actual:   $actual"
        FAIL=$((FAIL + 1))
    fi
}

assert_exit() {
    local desc="$1" expected_code="$2"
    shift 2
    TOTAL=$((TOTAL + 1))
    local actual_code=0
    "$@" >/dev/null 2>&1 || actual_code=$?
    if [[ "$expected_code" -eq "$actual_code" ]]; then
        echo -e "${GREEN}PASS${NC} $desc"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}FAIL${NC} $desc"
        echo "  Expected exit: $expected_code"
        echo "  Actual exit:   $actual_code"
        FAIL=$((FAIL + 1))
    fi
}

assert_match() {
    local desc="$1" pattern="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$actual" =~ $pattern ]]; then
        echo -e "${GREEN}PASS${NC} $desc"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}FAIL${NC} $desc"
        echo "  Pattern:  $pattern"
        echo "  Actual:   $actual"
        FAIL=$((FAIL + 1))
    fi
}

setup() {
    TEST_DIR=$(mktemp -d)
}

teardown() {
    if [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
}

# ═══════════════════════════════════════════
echo "═══ AutoCode dashboard.sh Tests ═══"
echo ""

# ─── Test 1: Missing JSONL file exits 1 ───
echo "--- missing JSONL file ---"
setup
assert_exit "dashboard: missing JSONL file exits 1" 1 \
    bash "$DASHBOARD_SCRIPT" --jsonl "$TEST_DIR/nonexistent.jsonl"
teardown

# ─── Test 2: Empty JSONL file exits 0 (warning) ───
echo ""
echo "--- empty JSONL file ---"
setup
touch "$TEST_DIR/empty.jsonl"
assert_exit "dashboard: empty JSONL file exits 0" 0 \
    bash "$DASHBOARD_SCRIPT" --jsonl "$TEST_DIR/empty.jsonl" --output "$TEST_DIR/out.html"
teardown

# ─── Test 3: Valid JSONL generates HTML output ───
echo ""
echo "--- valid JSONL generates HTML ---"
setup
cat > "$TEST_DIR/experiments.jsonl" <<'JSONL'
{"experiment_id":0,"commit":"abc1234","metric_name":"exec_time","metric_value":100.5,"prev_value":100.5,"delta":0,"delta_pct":0,"status":"baseline","description":"Baseline measurement","strategy":"","changed_files":[],"changed_lines":0,"gate_results":{},"timestamp":"2025-01-01T00:00:00Z","cumulative_improvement_pct":0,"metric_direction":"lower"}
{"experiment_id":1,"commit":"def5678","metric_name":"exec_time","metric_value":95.2,"prev_value":100.5,"delta":-5.3,"delta_pct":-5.3,"status":"keep","description":"Optimized loop","strategy":"algorithmic","changed_files":["src/algo.ts"],"changed_lines":10,"gate_results":{"test":"pass"},"timestamp":"2025-01-01T00:01:00Z","cumulative_improvement_pct":5.3,"metric_direction":"lower"}
{"experiment_id":2,"commit":"ghi9012","metric_name":"exec_time","metric_value":98.0,"prev_value":95.2,"delta":2.8,"delta_pct":2.9,"status":"discard","description":"Bad refactor","strategy":"structural","changed_files":["src/algo.ts"],"changed_lines":20,"gate_results":{"test":"pass"},"timestamp":"2025-01-01T00:02:00Z","cumulative_improvement_pct":5.3,"metric_direction":"lower"}
JSONL

OUTPUT_FILE="$TEST_DIR/dashboard.html"
assert_exit "dashboard: valid JSONL exits 0" 0 \
    bash "$DASHBOARD_SCRIPT" --jsonl "$TEST_DIR/experiments.jsonl" --output "$OUTPUT_FILE"

TOTAL=$((TOTAL + 1))
if [[ -f "$OUTPUT_FILE" ]]; then
    echo -e "${GREEN}PASS${NC} dashboard: HTML file created"
    PASS=$((PASS + 1))
else
    echo -e "${RED}FAIL${NC} dashboard: HTML file created"
    echo "  Expected file at: $OUTPUT_FILE"
    FAIL=$((FAIL + 1))
fi

# Check HTML contains expected content
TOTAL=$((TOTAL + 1))
if grep -q "AutoCode Dashboard" "$OUTPUT_FILE" 2>/dev/null; then
    echo -e "${GREEN}PASS${NC} dashboard: HTML contains title"
    PASS=$((PASS + 1))
else
    echo -e "${RED}FAIL${NC} dashboard: HTML contains title"
    FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if grep -q "exec_time" "$OUTPUT_FILE" 2>/dev/null; then
    echo -e "${GREEN}PASS${NC} dashboard: HTML contains metric name"
    PASS=$((PASS + 1))
else
    echo -e "${RED}FAIL${NC} dashboard: HTML contains metric name"
    FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if grep -q '"direction"' "$OUTPUT_FILE" 2>/dev/null; then
    echo -e "${GREEN}PASS${NC} dashboard: HTML contains direction data"
    PASS=$((PASS + 1))
else
    echo -e "${RED}FAIL${NC} dashboard: HTML contains direction data"
    FAIL=$((FAIL + 1))
fi
teardown

# ─── Test 4: Higher direction JSONL ───
echo ""
echo "--- higher direction ---"
setup
cat > "$TEST_DIR/higher.jsonl" <<'JSONL'
{"experiment_id":0,"commit":"aaa1111","metric_name":"coverage_pct","metric_value":70.0,"prev_value":70.0,"delta":0,"delta_pct":0,"status":"baseline","description":"Baseline","strategy":"","changed_files":[],"changed_lines":0,"gate_results":{},"timestamp":"2025-01-01T00:00:00Z","cumulative_improvement_pct":0,"metric_direction":"higher"}
{"experiment_id":1,"commit":"bbb2222","metric_name":"coverage_pct","metric_value":75.5,"prev_value":70.0,"delta":5.5,"delta_pct":7.9,"status":"keep","description":"Added tests","strategy":"micro","changed_files":["tests/new.test.ts"],"changed_lines":30,"gate_results":{"test":"pass"},"timestamp":"2025-01-01T00:01:00Z","cumulative_improvement_pct":7.9,"metric_direction":"higher"}
JSONL

OUTPUT_FILE="$TEST_DIR/higher.html"
assert_exit "dashboard: higher direction JSONL exits 0" 0 \
    bash "$DASHBOARD_SCRIPT" --jsonl "$TEST_DIR/higher.jsonl" --output "$OUTPUT_FILE"

TOTAL=$((TOTAL + 1))
if grep -q "higher" "$OUTPUT_FILE" 2>/dev/null; then
    echo -e "${GREEN}PASS${NC} dashboard: higher direction present in output"
    PASS=$((PASS + 1))
else
    echo -e "${RED}FAIL${NC} dashboard: higher direction present in output"
    FAIL=$((FAIL + 1))
fi
teardown

# ─── Test 5: Tag filter ───
echo ""
echo "--- tag filter ---"
setup
cat > "$TEST_DIR/tagged.jsonl" <<'JSONL'
{"experiment_id":0,"commit":"aaa","metric_name":"m","metric_value":10,"prev_value":10,"delta":0,"delta_pct":0,"status":"baseline","description":"Baseline alpha","strategy":"","changed_files":[],"changed_lines":0,"gate_results":{},"timestamp":"2025-01-01T00:00:00Z","cumulative_improvement_pct":0,"metric_direction":"lower"}
{"experiment_id":1,"commit":"bbb","metric_name":"m","metric_value":8,"prev_value":10,"delta":-2,"delta_pct":-20,"status":"keep","description":"Optimized beta","strategy":"","changed_files":[],"changed_lines":5,"gate_results":{},"timestamp":"2025-01-01T00:01:00Z","cumulative_improvement_pct":20,"metric_direction":"lower"}
JSONL

OUTPUT_FILE="$TEST_DIR/tagged.html"
assert_exit "dashboard: tag filter exits 0" 0 \
    bash "$DASHBOARD_SCRIPT" --jsonl "$TEST_DIR/tagged.jsonl" --output "$OUTPUT_FILE" --tag "alpha"
teardown

# ═══════════════════════════════════════════
echo ""
echo "═══════════════════════════════════════════"
echo " Results: $PASS passed, $FAIL failed, $TOTAL total"
echo "═══════════════════════════════════════════"

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
