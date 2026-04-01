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
# NOTE: gate.sh normalizes lower direction by negating scores.
#   raw 50 → composite -50, raw 40 → composite -40 (higher composite = better)
echo ""
echo "--- lower (normalized) + improvement → keep ---"
setup
make_state "-50.0" "lower"

assert_exit "lower + better composite (-40 > -50) → exit 0 (keep)" 0 bash "$JUDGE_SCRIPT" --current '{"_composite":{"score":-40.0}}'

teardown

# ─── Test 3: lower direction + worse → discard ───
echo ""
echo "--- lower (normalized) + worse → discard ---"
setup
make_state "-50.0" "lower"

assert_exit "lower + worse composite (-60 < -50) → exit 1 (discard)" 1 bash "$JUDGE_SCRIPT" --current '{"_composite":{"score":-60.0}}'

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
make_state "-50.0" "lower"

assert_exit "same score → exit 1 (discard)" 1 bash "$JUDGE_SCRIPT" --current '{"_composite":{"score":-50.0}}'

teardown

# ─── Test 7: keep → state best updated ───
echo ""
echo "--- keep updates best_score in state ---"
setup
make_state "-50.0" "lower"

bash "$JUDGE_SCRIPT" --current '{"_composite":{"score":-30.0}}' >/dev/null 2>&1 || true

BEST=$(grep -o '"best_score":[^,}]*' "$TEST_DIR/.autocode/state.json" | sed 's/"best_score"://')
assert_eq "best_score updated to -30.0" "-30.0" "$BEST"

teardown

# ─── Test 8: keep → best_commit updated ───
echo ""
echo "--- keep updates best_commit ---"
setup
make_state "-50.0" "lower"

bash "$JUDGE_SCRIPT" --current '{"_composite":{"score":-30.0}}' >/dev/null 2>&1 || true

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
make_state "-50.0" "lower"

OUTPUT=$(bash "$JUDGE_SCRIPT" --current '{"_composite":{"score":-40.0}}' 2>/dev/null) || true

assert_contains "output has verdict" "$OUTPUT" '"verdict"'
assert_contains "output has current_score" "$OUTPUT" '"current_score"'
assert_contains "output has best_score" "$OUTPUT" '"best_score"'
assert_contains "output has delta" "$OUTPUT" '"delta"'
assert_contains "output has delta_pct" "$OUTPUT" '"delta_pct"'

teardown

# ─── Test 10: negative scores work ───
# Normalized: best=-50 (raw 50), current=-40 (raw 40, improvement for lower)
echo ""
echo "--- negative scores ---"
setup
make_state "-50.0" "lower"

assert_exit "negative composite improvement (-40 > -50) → keep" 0 bash "$JUDGE_SCRIPT" --current '{"_composite":{"score":-40.0}}'

teardown

# ─── Test 11: best_score=0, no division by zero ───
echo ""
echo "--- best_score=0 → no division by zero ---"
setup
make_state "0" "higher"

EXIT_CODE=0
OUTPUT=$(bash "$JUDGE_SCRIPT" --current '{"_composite":{"score":10.0}}' 2>/dev/null) || EXIT_CODE=$?

TOTAL=$((TOTAL + 1))
# Should not crash; 10 > 0 → keep → exit 0
if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo -e "${GREEN}PASS${NC} best_score=0 does not crash (exit 0 = keep)"
    PASS=$((PASS + 1))
else
    echo -e "${RED}FAIL${NC} best_score=0 crashed or unexpected exit ($EXIT_CODE)"
    FAIL=$((FAIL + 1))
fi

# Verify delta_pct is 100 (since best=0, improvement from 0 to 10)
assert_contains "delta_pct is 100 when best_score=0" "$OUTPUT" '"delta_pct":100'

teardown

# ─── Test 12: best_score=0, same score → delta_pct=0 ───
echo ""
echo "--- best_score=0, same score → discard ---"
setup
make_state "0" "higher"

OUTPUT=$(bash "$JUDGE_SCRIPT" --current '{"_composite":{"score":0}}' 2>/dev/null) || true
assert_contains "delta_pct is 0 when both scores are 0" "$OUTPUT" '"delta_pct":0'

teardown

# ─── Test 13: Missing --current → exit 2 ───
echo ""
echo "--- missing --current → exit 2 ---"
setup
make_state "50.0" "lower"

assert_exit "missing --current → exit 2" 2 bash "$JUDGE_SCRIPT"

teardown

# ─── Test 14: Unparseable score in --current → exit 2 ───
echo ""
echo "--- unparseable score → exit 2 ---"
setup
make_state "50.0" "lower"

assert_exit "unparseable score → exit 2" 2 bash "$JUDGE_SCRIPT" --current '{"_composite":{"score":"not_a_number"}}'

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
