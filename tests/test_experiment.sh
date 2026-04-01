#!/usr/bin/env bash
# AutoCode experiment.sh Unit Tests
# Usage: bash tests/test_experiment.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
EXPERIMENT_SCRIPT="$PROJECT_DIR/scripts/experiment.sh"
GATE_SCRIPT="$PROJECT_DIR/scripts/gate.sh"
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
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"

    # Create minimal config
    cat > "$TEST_DIR/.autocode.yaml" <<'YAML'
objectives:
  - name: test_metric
    command: "echo 'score: 42.5'"
    parse: "([0-9.]+)"
    weight: 1.0
    direction: lower

gates:
  - name: check
    command: "echo ok"
    expect: exit_code_0
    optional: false

changeset:
  max_files: 5
  max_lines: 200

readonly:
  - "*.lock"
YAML

    git add -A
    git commit -q -m "init"
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
    if grep -q "$pattern" "$file" 2>/dev/null; then
        echo -e "${GREEN}PASS${NC} $desc"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}FAIL${NC} $desc (pattern not found: $pattern)"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_empty() {
    local desc="$1" value="$2"
    TOTAL=$((TOTAL + 1))
    if [[ -n "$value" ]]; then
        echo -e "${GREEN}PASS${NC} $desc"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}FAIL${NC} $desc (value is empty)"
        FAIL=$((FAIL + 1))
    fi
}

# ═══════════════════════════════════════════
echo "═══ AutoCode experiment.sh Tests ═══"
echo ""

# ─── Test 1: start creates branch ───
echo "--- start: creates branch ---"
setup

bash "$EXPERIMENT_SCRIPT" start --config "$TEST_DIR/.autocode.yaml" --tag "test001" >/dev/null 2>&1

CURRENT_BRANCH=$(git branch --show-current)
assert_eq "start creates autocode/ branch" "autocode/test001" "$CURRENT_BRANCH"

teardown

# ─── Test 2: start creates state.json ───
echo ""
echo "--- start: creates state.json ---"
setup

bash "$EXPERIMENT_SCRIPT" start --config "$TEST_DIR/.autocode.yaml" --tag "test002" >/dev/null 2>&1

assert_file_exists "state.json created" "$TEST_DIR/.autocode/state.json"
assert_contains "state.json has branch" "$TEST_DIR/.autocode/state.json" '"branch":"autocode/test002"'
assert_contains "state.json has experiment_id 0" "$TEST_DIR/.autocode/state.json" '"experiment_id":0'

teardown

# ─── Test 3: start measures baseline ───
echo ""
echo "--- start: measures baseline ---"
setup

bash "$EXPERIMENT_SCRIPT" start --config "$TEST_DIR/.autocode.yaml" --tag "test003" >/dev/null 2>&1

# Baseline score should not be null
BASELINE=$(grep -o '"baseline_score":[^,}]*' "$TEST_DIR/.autocode/state.json" 2>/dev/null | sed 's/"baseline_score"://')
TOTAL=$((TOTAL + 1))
if [[ "$BASELINE" != "null" && -n "$BASELINE" ]]; then
    echo -e "${GREEN}PASS${NC} baseline_score is measured (got: $BASELINE)"
    PASS=$((PASS + 1))
else
    echo -e "${RED}FAIL${NC} baseline_score should not be null (got: $BASELINE)"
    FAIL=$((FAIL + 1))
fi

teardown

# ─── Test 4: start on dirty tree → auto-commit ───
echo ""
echo "--- start: dirty tree → auto-commit ---"
setup

# Make the working tree dirty
echo "dirty" > "$TEST_DIR/dirty_file.txt"

assert_exit "start auto-commits dirty tree" 0 bash "$EXPERIMENT_SCRIPT" start --config "$TEST_DIR/.autocode.yaml" --tag "dirty"

teardown

# ─── Test 5: commit increments experiment_id ───
echo ""
echo "--- commit: increments experiment_id ---"
setup

bash "$EXPERIMENT_SCRIPT" start --config "$TEST_DIR/.autocode.yaml" --tag "test005" >/dev/null 2>&1

# Make a change and commit
echo "change1" > "$TEST_DIR/file1.txt"
bash "$EXPERIMENT_SCRIPT" commit --config "$TEST_DIR/.autocode.yaml" --message "first change" >/dev/null 2>&1

EXP_ID=$(grep -o '"experiment_id":[0-9]*' "$TEST_DIR/.autocode/state.json" | sed 's/"experiment_id"://')
assert_eq "experiment_id is 1 after first commit" "1" "$EXP_ID"

# Second commit
echo "change2" > "$TEST_DIR/file2.txt"
bash "$EXPERIMENT_SCRIPT" commit --config "$TEST_DIR/.autocode.yaml" --message "second change" >/dev/null 2>&1

EXP_ID=$(grep -o '"experiment_id":[0-9]*' "$TEST_DIR/.autocode/state.json" | sed 's/"experiment_id"://')
assert_eq "experiment_id is 2 after second commit" "2" "$EXP_ID"

teardown

# ─── Test 6: commit appears in git log ───
echo ""
echo "--- commit: appears in git log ---"
setup

bash "$EXPERIMENT_SCRIPT" start --config "$TEST_DIR/.autocode.yaml" --tag "test006" >/dev/null 2>&1

echo "new content" > "$TEST_DIR/src.txt"
bash "$EXPERIMENT_SCRIPT" commit --config "$TEST_DIR/.autocode.yaml" --message "add src" >/dev/null 2>&1

GIT_LOG=$(git log --oneline -1)
TOTAL=$((TOTAL + 1))
if echo "$GIT_LOG" | grep -q "autocode: add src"; then
    echo -e "${GREEN}PASS${NC} commit message in git log"
    PASS=$((PASS + 1))
else
    echo -e "${RED}FAIL${NC} commit message not found in git log (got: $GIT_LOG)"
    FAIL=$((FAIL + 1))
fi

teardown

# ─── Test 7: commit without --message → error ───
echo ""
echo "--- commit: missing --message → error ---"
setup

bash "$EXPERIMENT_SCRIPT" start --config "$TEST_DIR/.autocode.yaml" --tag "test007" >/dev/null 2>&1

echo "stuff" > "$TEST_DIR/stuff.txt"

assert_exit "commit fails without --message" 1 bash "$EXPERIMENT_SCRIPT" commit --config "$TEST_DIR/.autocode.yaml"

teardown

# ─── Test 8: discard resets to HEAD~1 ───
echo ""
echo "--- discard: resets HEAD~1 ---"
setup

bash "$EXPERIMENT_SCRIPT" start --config "$TEST_DIR/.autocode.yaml" --tag "test008" >/dev/null 2>&1

# Record HEAD before change
HEAD_BEFORE=$(git rev-parse HEAD)

echo "experiment" > "$TEST_DIR/experiment.txt"
bash "$EXPERIMENT_SCRIPT" commit --config "$TEST_DIR/.autocode.yaml" --message "to discard" >/dev/null 2>&1

# Now discard
bash "$EXPERIMENT_SCRIPT" discard >/dev/null 2>&1

HEAD_AFTER=$(git rev-parse HEAD)
assert_eq "discard resets to previous HEAD" "$HEAD_BEFORE" "$HEAD_AFTER"

teardown

# ─── Test 9: status output format ───
echo ""
echo "--- status: output format ---"
setup

bash "$EXPERIMENT_SCRIPT" start --config "$TEST_DIR/.autocode.yaml" --tag "test009" >/dev/null 2>&1

STATUS_OUTPUT=$(bash "$EXPERIMENT_SCRIPT" status --config "$TEST_DIR/.autocode.yaml" 2>/dev/null)

TOTAL=$((TOTAL + 1))
if echo "$STATUS_OUTPUT" | grep -q "Branch:"; then
    echo -e "${GREEN}PASS${NC} status shows Branch"
    PASS=$((PASS + 1))
else
    echo -e "${RED}FAIL${NC} status missing Branch field"
    FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if echo "$STATUS_OUTPUT" | grep -q "Experiment:"; then
    echo -e "${GREEN}PASS${NC} status shows Experiment"
    PASS=$((PASS + 1))
else
    echo -e "${RED}FAIL${NC} status missing Experiment field"
    FAIL=$((FAIL + 1))
fi

teardown

# ─── Test 10: status without state.json → error ───
echo ""
echo "--- status: no state.json → error ---"
setup

assert_exit "status fails without state.json" 1 bash "$EXPERIMENT_SCRIPT" status --config "$TEST_DIR/.autocode.yaml"

teardown

# ─── Test 11: start with auto-generated tag ───
echo ""
echo "--- start: auto-generated tag ---"
setup

bash "$EXPERIMENT_SCRIPT" start --config "$TEST_DIR/.autocode.yaml" >/dev/null 2>&1

CURRENT_BRANCH=$(git branch --show-current)
TOTAL=$((TOTAL + 1))
if [[ "$CURRENT_BRANCH" =~ ^autocode/[0-9]{8}-[0-9]{6}-[0-9a-f]{4}$ ]]; then
    echo -e "${GREEN}PASS${NC} auto-generated tag matches YYYYMMDD-HHMMSS-XXXX"
    PASS=$((PASS + 1))
else
    echo -e "${RED}FAIL${NC} auto-generated tag format wrong (got: $CURRENT_BRANCH)"
    FAIL=$((FAIL + 1))
fi

teardown

# ─── Test 12: commit returns hash ───
echo ""
echo "--- commit: returns hash ---"
setup

bash "$EXPERIMENT_SCRIPT" start --config "$TEST_DIR/.autocode.yaml" --tag "test012" >/dev/null 2>&1

echo "content" > "$TEST_DIR/myfile.txt"
COMMIT_OUTPUT=$(bash "$EXPERIMENT_SCRIPT" commit --config "$TEST_DIR/.autocode.yaml" --message "hash test" 2>/dev/null)

TOTAL=$((TOTAL + 1))
if echo "$COMMIT_OUTPUT" | grep -qE '[0-9a-f]{7}'; then
    echo -e "${GREEN}PASS${NC} commit outputs hash"
    PASS=$((PASS + 1))
else
    echo -e "${RED}FAIL${NC} commit did not output hash (got: $COMMIT_OUTPUT)"
    FAIL=$((FAIL + 1))
fi

teardown

# ─── Test 13: commit changeset max_files limit ───
echo ""
echo "--- commit: changeset max_files limit ---"
setup

# Override config with max_files: 1
cat > "$TEST_DIR/.autocode.yaml" <<'YAML'
objectives:
  - name: test_metric
    command: "echo 'score: 42.5'"
    parse: "([0-9.]+)"
    weight: 1.0
    direction: lower

gates:
  - name: check
    command: "echo ok"
    expect: exit_code_0
    optional: false

changeset:
  max_files: 1
  max_lines: 200

readonly:
  - "*.lock"
YAML

git add -A && git commit -q -m "update config"

bash "$EXPERIMENT_SCRIPT" start --config "$TEST_DIR/.autocode.yaml" --tag "test013" >/dev/null 2>&1

# Create 2 new files (exceeds max_files: 1)
echo "file1 content" > "$TEST_DIR/new_file1.txt"
echo "file2 content" > "$TEST_DIR/new_file2.txt"

assert_exit "commit fails with too many files" 1 bash "$EXPERIMENT_SCRIPT" commit --config "$TEST_DIR/.autocode.yaml" --message "too many files"

# Verify error message mentions "Changeset too large"
OUTPUT=$(bash "$EXPERIMENT_SCRIPT" commit --config "$TEST_DIR/.autocode.yaml" --message "too many files" 2>&1 || true)
TOTAL=$((TOTAL + 1))
if echo "$OUTPUT" | grep -q "Changeset too large"; then
    echo -e "${GREEN}PASS${NC} error message contains 'Changeset too large'"
    PASS=$((PASS + 1))
else
    echo -e "${RED}FAIL${NC} error message missing 'Changeset too large' (got: $OUTPUT)"
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
