#!/usr/bin/env bash
# AutoCode Integration Tests — Full Experiment Lifecycle
# Usage: bash tests/test_integration.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
EXPERIMENT_SCRIPT="$PROJECT_DIR/scripts/experiment.sh"
GATE_SCRIPT="$PROJECT_DIR/scripts/gate.sh"
JUDGE_SCRIPT="$PROJECT_DIR/scripts/judge.sh"
MEMORY_SCRIPT="$PROJECT_DIR/scripts/memory.sh"
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

assert_file_exists() {
    local desc="$1" filepath="$2"
    TOTAL=$((TOTAL + 1))
    if [[ -f "$filepath" ]]; then
        echo -e "${GREEN}PASS${NC} $desc"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}FAIL${NC} $desc"
        echo "  File not found: $filepath"
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

setup_project() {
    TEST_DIR=$(mktemp -d)
    cd "$TEST_DIR"

    # Initialize git repo
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"

    # Create a simple project with a "metric" we can measure
    mkdir -p src
    echo 'echo "score: 42.5"' > src/bench.sh

    # Create .autocode.yaml with echo-based gates/metrics
    cat > .autocode.yaml <<'YAML'
target_files:
  - src/

gates:
  - name: check
    command: "echo ok"
    expect: exit_code_0
    optional: false

objectives:
  - name: test_metric
    command: "bash src/bench.sh"
    parse: "([0-9.]+)"
    weight: 1.0
    direction: lower

readonly:
  - "*.lock"

changeset:
  max_files: 5
  max_lines: 200
YAML

    git add -A
    git commit -q -m "Initial project"
}

teardown() {
    if [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]]; then
        cd /
        rm -rf "$TEST_DIR"
    fi
}

# ═══════════════════════════════════════════
echo "═══ AutoCode Integration Tests ═══"
echo ""

# ─── Full Lifecycle Test ───
echo "--- Full experiment lifecycle ---"
setup_project

# Step 1: experiment start
echo ""
echo "Step 1: experiment.sh start"
assert_exit "lifecycle: experiment start exits 0" 0 \
    bash "$EXPERIMENT_SCRIPT" start --config .autocode.yaml --tag "integ-test"

# Step 2: state.json created
echo ""
echo "Step 2: verify state.json"
assert_file_exists "lifecycle: state.json exists" "$TEST_DIR/.autocode/state.json"

# Verify state.json has expected fields
TOTAL=$((TOTAL + 1))
if grep -q '"branch"' "$TEST_DIR/.autocode/state.json" 2>/dev/null; then
    echo -e "${GREEN}PASS${NC} lifecycle: state.json has branch field"
    PASS=$((PASS + 1))
else
    echo -e "${RED}FAIL${NC} lifecycle: state.json has branch field"
    FAIL=$((FAIL + 1))
fi

# Verify we're on the autocode branch
TOTAL=$((TOTAL + 1))
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)
if [[ "$CURRENT_BRANCH" == "autocode/integ-test" ]]; then
    echo -e "${GREEN}PASS${NC} lifecycle: on autocode/integ-test branch"
    PASS=$((PASS + 1))
else
    echo -e "${RED}FAIL${NC} lifecycle: on autocode/integ-test branch"
    echo "  Actual branch: $CURRENT_BRANCH"
    FAIL=$((FAIL + 1))
fi

# Step 3: make a change and commit
echo ""
echo "Step 3: experiment.sh commit"
echo 'echo "score: 40.0"' > src/bench.sh
assert_exit "lifecycle: experiment commit exits 0" 0 \
    bash "$EXPERIMENT_SCRIPT" commit --config .autocode.yaml --message "Improve metric"

# Step 4: run gates
echo ""
echo "Step 4: gate.sh gates"
GATE_OUTPUT=""
GATE_EXIT=0
GATE_OUTPUT=$(bash "$GATE_SCRIPT" gates --config .autocode.yaml 2>/dev/null) || GATE_EXIT=$?
assert_eq "lifecycle: gates pass (exit 0)" "0" "$GATE_EXIT"
assert_match "lifecycle: gate output contains check=pass" 'check.*pass' "$GATE_OUTPUT"

# Step 5: run measure
echo ""
echo "Step 5: gate.sh measure"
MEASURE_OUTPUT=""
MEASURE_EXIT=0
MEASURE_OUTPUT=$(bash "$GATE_SCRIPT" measure --config .autocode.yaml 2>/dev/null) || MEASURE_EXIT=$?
assert_eq "lifecycle: measure exits 0" "0" "$MEASURE_EXIT"
assert_match "lifecycle: measure output has composite score" '_composite' "$MEASURE_OUTPUT"

# Step 6: run judge
echo ""
echo "Step 6: judge.sh"
JUDGE_EXIT=0
JUDGE_OUTPUT=$(bash "$JUDGE_SCRIPT" --config .autocode.yaml --current "$MEASURE_OUTPUT" 2>/dev/null) || JUDGE_EXIT=$?

# Judge should return keep (0) or discard (1) — either is valid for integration test
TOTAL=$((TOTAL + 1))
if [[ "$JUDGE_EXIT" -eq 0 || "$JUDGE_EXIT" -eq 1 ]]; then
    echo -e "${GREEN}PASS${NC} lifecycle: judge exits 0 or 1 (got $JUDGE_EXIT)"
    PASS=$((PASS + 1))
else
    echo -e "${RED}FAIL${NC} lifecycle: judge exits 0 or 1"
    echo "  Actual exit: $JUDGE_EXIT"
    FAIL=$((FAIL + 1))
fi

assert_match "lifecycle: judge output has verdict" 'verdict' "$JUDGE_OUTPUT"

# Step 7: run gate.sh log
echo ""
echo "Step 7: gate.sh log"
COMMIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "test123")
assert_exit "lifecycle: gate.sh log exits 0" 0 \
    bash "$GATE_SCRIPT" log --config .autocode.yaml \
        --commit "$COMMIT_HASH" --value "40.0" --prev "42.5" --delta "-2.5" \
        --status "keep" --description "Improve metric" \
        --strategy "algorithmic" --experiment-id "1" --delta-pct "-5.9" \
        --cumulative-pct "5.9" --direction "lower"

# Verify JSONL log was written
assert_file_exists "lifecycle: experiments.jsonl exists" "$TEST_DIR/.autocode/logs/experiments.jsonl"

TOTAL=$((TOTAL + 1))
JSONL_LINES=$(wc -l < "$TEST_DIR/.autocode/logs/experiments.jsonl" 2>/dev/null | tr -d ' ')
if [[ "$JSONL_LINES" -ge 1 ]]; then
    echo -e "${GREEN}PASS${NC} lifecycle: JSONL has entries ($JSONL_LINES lines)"
    PASS=$((PASS + 1))
else
    echo -e "${RED}FAIL${NC} lifecycle: JSONL has entries"
    echo "  Lines: $JSONL_LINES"
    FAIL=$((FAIL + 1))
fi

# Step 8: run memory.sh update
echo ""
echo "Step 8: memory.sh update"
assert_exit "lifecycle: memory.sh update exits 0" 0 \
    bash "$MEMORY_SCRIPT" update --config .autocode.yaml

# Verify memory.md generated
assert_file_exists "lifecycle: memory.md exists" "$TEST_DIR/.autocode/memory.md"

TOTAL=$((TOTAL + 1))
if grep -q "Experiment Memory" "$TEST_DIR/.autocode/memory.md" 2>/dev/null; then
    echo -e "${GREEN}PASS${NC} lifecycle: memory.md has expected content"
    PASS=$((PASS + 1))
else
    echo -e "${RED}FAIL${NC} lifecycle: memory.md has expected content"
    FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if grep -q "What Worked" "$TEST_DIR/.autocode/memory.md" 2>/dev/null; then
    echo -e "${GREEN}PASS${NC} lifecycle: memory.md has What Worked section"
    PASS=$((PASS + 1))
else
    echo -e "${RED}FAIL${NC} lifecycle: memory.md has What Worked section"
    FAIL=$((FAIL + 1))
fi

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
