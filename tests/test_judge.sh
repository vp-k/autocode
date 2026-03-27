#!/usr/bin/env bash
# AutoCode judge.sh Unit Tests
# Usage: bash tests/test_judge.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
JUDGE_SCRIPT="$PROJECT_DIR/scripts/judge.sh"
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
    git commit -q -m "init" --allow-empty
    mkdir -p .autocode/logs
}

# Create state.json with given values
# Usage: make_state best_score direction [baseline_score]
make_state() {
    local best="$1" direction="$2" baseline="${3:-$1}"
    cat > "$TEST_DIR/.autocode/state.json" <<EOF
{"branch":"autocode/test","experiment_id":1,"baseline_score":${baseline},"best_score":${best},"best_commit":"abc1234","direction":"${direction}"}
EOF
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

assert_contains() {
    local desc="$1" text="$2" pattern="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$text" | grep -q "$pattern" 2>/dev/null; then
        echo -e "${GREEN}PASS${NC} $desc"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}FAIL${NC} $desc (pattern not found: $pattern in: $text)"
        FAIL=$((FAIL + 1))
    fi
}

# ═══════════════════════════════════════════
echo "═══ AutoCode judge.sh Tests ═══"
echo ""

# ─── Test 1: Baseline → keep + state update ───
echo "--- baseline: null baseline → keep ---"
setup

# State with null baseline
cat > "$TEST_DIR/.autocode/state.json" <<'EOF'
{"branch":"autocode/test","experiment_id":0,"baseline_score":null,"best_score":null,"best_commit":null,"direction":"lower"}
EOF

OUTPUT=$(bash "$JUDGE_SCRIPT" --current '{"_composite":{"score":50.0}}' 2>/dev/null) || true
assert_contains "baseline returns keep verdict" "$OUTPUT" '"verdict":"keep"'

# Check state was updated
BASELINE=$(grep -o '"baseline_score":[^,}]*' "$TEST_DIR/.autocode/state.json" | sed 's/"baseline_score"://')
assert_eq "baseline_score updated to 50.0" "50.0" "$BASELINE"

BEST=$(grep -o '"best_score":[^,}]*' "$TEST_DIR/.autocode/state.json" | sed 's/"best_score"://')
assert_eq "best_score updated to 50.0" "50.0" "$BEST"

teardown

# ─── Test 2: lower direction + improvement → keep ───
echo ""
echo "--- lower + improvement → keep ---"
setup
make_state "50.0" "lower"

assert_exit "lower + better score → exit 0 (keep)" 0 bash "$JUDGE_SCRIPT" --current '{"_composite":{"score":40.0}}'

teardown

# ─── Test 3: lower direction + worse → discard ───
echo ""
echo "--- lower + worse → discard ---"
setup
make_state "50.0" "lower"

assert_exit "lower + worse score → exit 1 (discard)" 1 bash "$JUDGE_SCRIPT" --current '{"_composite":{"score":60.0}}'

teardown

# ─── Test 4: higher direction + improvement → keep ───
echo ""
echo "--- higher + improvement → keep ---"
setup
make_state "50.0" "higher"

assert_exit "higher + better score → exit 0 (keep)" 0 bash "$JUDGE_SCRIPT" --current '{"_composite":{"score":70.0}}'

teardown

# ─── Test 5: higher direction + worse → discard ───
echo ""
echo "--- higher + worse → discard ---"
setup
make_state "50.0" "higher"

assert_exit "higher + worse score → exit 1 (discard)" 1 bash "$JUDGE_SCRIPT" --current '{"_composite":{"score":30.0}}'

teardown

# ─── Test 6: same score → discard ───
echo ""
echo "--- same score → discard ---"
setup
make_state "50.0" "lower"

assert_exit "same score → exit 1 (discard)" 1 bash "$JUDGE_SCRIPT" --current '{"_composite":{"score":50.0}}'

teardown

# ─── Test 7: keep → state best updated ───
echo ""
echo "--- keep updates best_score in state ---"
setup
make_state "50.0" "lower"

bash "$JUDGE_SCRIPT" --current '{"_composite":{"score":30.0}}' >/dev/null 2>&1 || true

BEST=$(grep -o '"best_score":[^,}]*' "$TEST_DIR/.autocode/state.json" | sed 's/"best_score"://')
assert_eq "best_score updated to 30.0" "30.0" "$BEST"

teardown

# ─── Test 8: keep → best_commit updated ───
echo ""
echo "--- keep updates best_commit ---"
setup
make_state "50.0" "lower"

bash "$JUDGE_SCRIPT" --current '{"_composite":{"score":30.0}}' >/dev/null 2>&1 || true

BEST_COMMIT=$(grep -o '"best_commit":"[^"]*"' "$TEST_DIR/.autocode/state.json" | sed 's/"best_commit":"//;s/"//')
TOTAL=$((TOTAL + 1))
if [[ -n "$BEST_COMMIT" && "$BEST_COMMIT" != "null" ]]; then
    echo -e "${GREEN}PASS${NC} best_commit updated"
    PASS=$((PASS + 1))
else
    echo -e "${RED}FAIL${NC} best_commit not updated (got: $BEST_COMMIT)"
    FAIL=$((FAIL + 1))
fi

teardown

# ─── Test 9: JSON output has all fields ───
echo ""
echo "--- JSON output completeness ---"
setup
make_state "50.0" "lower"

OUTPUT=$(bash "$JUDGE_SCRIPT" --current '{"_composite":{"score":40.0}}' 2>/dev/null) || true

assert_contains "output has verdict" "$OUTPUT" '"verdict"'
assert_contains "output has current_score" "$OUTPUT" '"current_score"'
assert_contains "output has best_score" "$OUTPUT" '"best_score"'
assert_contains "output has delta" "$OUTPUT" '"delta"'
assert_contains "output has delta_pct" "$OUTPUT" '"delta_pct"'

teardown

# ─── Test 10: negative scores work ───
echo ""
echo "--- negative scores ---"
setup
make_state "-50.0" "lower"

assert_exit "negative score improvement → keep" 0 bash "$JUDGE_SCRIPT" --current '{"_composite":{"score":-60.0}}'

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
