#!/usr/bin/env bash
# AutoCode memory.sh Unit Tests
# Usage: bash tests/test_memory.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MEMORY_SCRIPT="$PROJECT_DIR/scripts/memory.sh"
TEST_DIR=""
PASS=0
FAIL=0
TOTAL=0

# ─── Helpers ───
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

setup() {
    TEST_DIR=$(mktemp -d)
    cd "$TEST_DIR"
    mkdir -p .autocode/logs

    # Create minimal config
    cat > "$TEST_DIR/.autocode.yaml" <<'YAML'
objectives:
  - name: test_metric
    command: "echo 42"
    parse: "([0-9]+)"
    weight: 1.0
    direction: lower
YAML
}

# Create state.json
make_state() {
    local best_score="${1:-42.0}" best_commit="${2:-abc1234}"
    cat > "$TEST_DIR/.autocode/state.json" <<EOF
{"branch":"autocode/test","experiment_id":3,"baseline_score":100.0,"best_score":${best_score},"best_commit":"${best_commit}","direction":"lower"}
EOF
}

# Append a JSONL experiment entry
add_experiment() {
    local status="$1" desc="$2" strategy="${3:-}" delta_pct="${4:-0}"
    echo "{\"experiment_id\":1,\"commit\":\"abc123\",\"metric_name\":\"test_metric\",\"metric_value\":42,\"prev_value\":50,\"delta\":-8,\"delta_pct\":${delta_pct},\"status\":\"${status}\",\"description\":\"${desc}\",\"strategy\":\"${strategy}\",\"changed_files\":[],\"changed_lines\":5,\"gate_results\":{},\"timestamp\":\"2025-01-01T00:00:00Z\",\"cumulative_improvement_pct\":0,\"metric_direction\":\"lower\"}" >> "$TEST_DIR/.autocode/logs/experiments.jsonl"
}

teardown() {
    cd /
    rm -rf "$TEST_DIR" 2>/dev/null || true
}

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

assert_file_exists() {
    local desc="$1" file="$2"
    TOTAL=$((TOTAL + 1))
    if [[ -f "$file" ]]; then
        echo -e "${GREEN}PASS${NC} $desc"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}FAIL${NC} $desc (file not found: $file)"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1" file="$2" pattern="$3"
    TOTAL=$((TOTAL + 1))
    if grep -q -- "$pattern" "$file" 2>/dev/null; then
        echo -e "${GREEN}PASS${NC} $desc"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}FAIL${NC} $desc (pattern not found: $pattern)"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    local desc="$1" file="$2" pattern="$3"
    TOTAL=$((TOTAL + 1))
    if ! grep -q -- "$pattern" "$file" 2>/dev/null; then
        echo -e "${GREEN}PASS${NC} $desc"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}FAIL${NC} $desc (pattern unexpectedly found: $pattern)"
        FAIL=$((FAIL + 1))
    fi
}

# ═══════════════════════════════════════════
echo "═══ AutoCode memory.sh Tests ═══"
echo ""

# ─── Test 1: Empty JSONL → initial memory ───
echo "--- empty JSONL: initial memory ---"
setup
make_state "100.0" "none"
touch "$TEST_DIR/.autocode/logs/experiments.jsonl"

bash "$MEMORY_SCRIPT" update --config "$TEST_DIR/.autocode.yaml" >/dev/null 2>&1

assert_file_exists "memory.md created" "$TEST_DIR/.autocode/memory.md"
assert_contains "has What Worked section" "$TEST_DIR/.autocode/memory.md" "What Worked"
assert_contains "has What Failed section" "$TEST_DIR/.autocode/memory.md" "What Failed"
assert_contains "has no successful experiments message" "$TEST_DIR/.autocode/memory.md" "no successful experiments"

teardown

# ─── Test 2: keep experiment → What Worked ───
echo ""
echo "--- keep experiment: What Worked ---"
setup
make_state "42.0" "abc1234"
add_experiment "keep" "Optimized inner loop" "algorithmic" "-15.5"

bash "$MEMORY_SCRIPT" update --config "$TEST_DIR/.autocode.yaml" >/dev/null 2>&1

assert_contains "What Worked has description" "$TEST_DIR/.autocode/memory.md" "Optimized inner loop"
assert_contains "What Worked has delta" "$TEST_DIR/.autocode/memory.md" "-15.5"

teardown

# ─── Test 3: discard experiment → What Failed ───
echo ""
echo "--- discard experiment: What Failed ---"
setup
make_state "42.0" "abc1234"
add_experiment "discard" "Bad refactoring attempt" "structural" "5.0"

bash "$MEMORY_SCRIPT" update --config "$TEST_DIR/.autocode.yaml" >/dev/null 2>&1

assert_contains "What Failed has description" "$TEST_DIR/.autocode/memory.md" "Bad refactoring attempt"
assert_contains "What Failed has status" "$TEST_DIR/.autocode/memory.md" "discard"

teardown

# ─── Test 4: crash experiment → What Failed ───
echo ""
echo "--- crash experiment: What Failed ---"
setup
make_state "42.0" "abc1234"
add_experiment "crash" "Runtime error in build" "micro" "0"

bash "$MEMORY_SCRIPT" update --config "$TEST_DIR/.autocode.yaml" >/dev/null 2>&1

assert_contains "What Failed has crash entry" "$TEST_DIR/.autocode/memory.md" "Runtime error in build"
assert_contains "What Failed shows crash status" "$TEST_DIR/.autocode/memory.md" "crash"

teardown

# ─── Test 5: Current Best accuracy ───
echo ""
echo "--- Current Best accuracy ---"
setup
make_state "35.7" "def5678"
add_experiment "keep" "Some optimization" "algorithmic" "-10.0"

bash "$MEMORY_SCRIPT" update --config "$TEST_DIR/.autocode.yaml" >/dev/null 2>&1

assert_contains "Current Best has score" "$TEST_DIR/.autocode/memory.md" "35.7"
assert_contains "Current Best has commit" "$TEST_DIR/.autocode/memory.md" "def5678"

teardown

# ─── Test 6: Unexplored strategies ───
echo ""
echo "--- Unexplored strategies ---"
setup
make_state "42.0" "abc1234"
add_experiment "keep" "Algorithm change" "algorithmic" "-10.0"
add_experiment "discard" "Micro opt" "micro" "5.0"

bash "$MEMORY_SCRIPT" update --config "$TEST_DIR/.autocode.yaml" >/dev/null 2>&1

# algorithmic and micro are used, so structural/config/elimination should be unexplored
assert_contains "Unexplored has structural" "$TEST_DIR/.autocode/memory.md" "Structural refactoring"
assert_contains "Unexplored has config" "$TEST_DIR/.autocode/memory.md" "Configuration tuning"
assert_contains "Unexplored has elimination" "$TEST_DIR/.autocode/memory.md" "Code elimination"
assert_not_contains "Unexplored does not have algorithmic" "$TEST_DIR/.autocode/memory.md" "Algorithmic changes"
assert_not_contains "Unexplored does not have micro" "$TEST_DIR/.autocode/memory.md" "Micro-optimizations"

teardown

# ─── Test 7: All strategies explored ───
echo ""
echo "--- all strategies explored ---"
setup
make_state "42.0" "abc1234"
add_experiment "keep" "algo" "algorithmic" "-1"
add_experiment "keep" "micro" "micro" "-1"
add_experiment "keep" "struct" "structural" "-1"
add_experiment "keep" "conf" "config" "-1"
add_experiment "keep" "elim" "elimination" "-1"

bash "$MEMORY_SCRIPT" update --config "$TEST_DIR/.autocode.yaml" >/dev/null 2>&1

assert_contains "all strategies explored message" "$TEST_DIR/.autocode/memory.md" "all strategies explored"

teardown

# ─── Test 8: gate_fail → What Failed ───
echo ""
echo "--- gate_fail: What Failed ---"
setup
make_state "42.0" "abc1234"
add_experiment "gate_fail" "Build broke" "structural" "0"

bash "$MEMORY_SCRIPT" update --config "$TEST_DIR/.autocode.yaml" >/dev/null 2>&1

assert_contains "What Failed has gate_fail" "$TEST_DIR/.autocode/memory.md" "Build broke"
assert_contains "What Failed shows gate_fail status" "$TEST_DIR/.autocode/memory.md" "gate_fail"

teardown

# ─── Test 9: Manual Notes preservation ───
echo ""
echo "--- manual notes preservation ---"
setup
make_state "42.0" "abc1234"
add_experiment "keep" "Some optimization" "algorithmic" "-10.0"

# Pre-create memory.md with a Manual Notes section
cat > "$TEST_DIR/.autocode/memory.md" <<'MD'
## Experiment Memory

### What Worked
(old content)

### Manual Notes
This is my custom note.
Do not delete this.
MD

bash "$MEMORY_SCRIPT" update --config "$TEST_DIR/.autocode.yaml" >/dev/null 2>&1

assert_contains "Manual Notes section preserved" "$TEST_DIR/.autocode/memory.md" "### Manual Notes"
assert_contains "Manual Notes content preserved" "$TEST_DIR/.autocode/memory.md" "This is my custom note."
assert_contains "Manual Notes multi-line preserved" "$TEST_DIR/.autocode/memory.md" "Do not delete this."

teardown

# ─── Test 10: Empty description → (no description) ───
echo ""
echo "--- empty description fallback ---"
setup
make_state "42.0" "abc1234"

# Add entry with empty description
echo '{"experiment_id":1,"commit":"abc123","metric_name":"test_metric","metric_value":42,"prev_value":50,"delta":-8,"delta_pct":-15,"status":"keep","description":"","strategy":"algorithmic","changed_files":[],"changed_lines":5,"gate_results":{},"timestamp":"2025-01-01T00:00:00Z","cumulative_improvement_pct":0,"metric_direction":"lower"}' >> "$TEST_DIR/.autocode/logs/experiments.jsonl"

bash "$MEMORY_SCRIPT" update --config "$TEST_DIR/.autocode.yaml" >/dev/null 2>&1

assert_contains "empty description shows fallback" "$TEST_DIR/.autocode/memory.md" "(no description)"

teardown

# ─── Test 11: No JSONL file → valid memory.md ───
echo ""
echo "--- no JSONL file ---"
setup
make_state "42.0" "abc1234"

# Ensure no JSONL file exists
rm -f "$TEST_DIR/.autocode/logs/experiments.jsonl"

bash "$MEMORY_SCRIPT" update --config "$TEST_DIR/.autocode.yaml" >/dev/null 2>&1
EXIT_CODE=$?

TOTAL=$((TOTAL + 1))
if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo -e "${GREEN}PASS${NC} no JSONL: exits 0"
    PASS=$((PASS + 1))
else
    echo -e "${RED}FAIL${NC} no JSONL: expected exit 0, got $EXIT_CODE"
    FAIL=$((FAIL + 1))
fi

assert_file_exists "no JSONL: memory.md created" "$TEST_DIR/.autocode/memory.md"
assert_contains "no JSONL: has What Worked section" "$TEST_DIR/.autocode/memory.md" "What Worked"
assert_contains "no JSONL: has What Failed section" "$TEST_DIR/.autocode/memory.md" "What Failed"

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
