#!/usr/bin/env bash
# AutoCode Configuration Parsing Tests
# Tests that various .autocode.yaml configurations are correctly parsed
# Usage: bash tests/test_config.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GATE_SCRIPT="$PROJECT_DIR/scripts/gate.sh"
PASS=0
FAIL=0
TOTAL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

assert_output_contains() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$actual" | grep -q "$expected"; then
        echo -e "${GREEN}PASS${NC} $desc"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}FAIL${NC} $desc"
        echo "  Expected to contain: $expected"
        echo "  Actual output: $actual"
        FAIL=$((FAIL + 1))
    fi
}

echo "═══ AutoCode Config Parsing Tests ═══"
echo ""

# ─── Test: Example config is valid ───
echo "--- example config ---"
OUTPUT=$(bash "$GATE_SCRIPT" parse-config --config "$PROJECT_DIR/examples/.autocode.yaml" 2>&1)
assert_output_contains "example: has build gate" "build" "$OUTPUT"
assert_output_contains "example: has test gate" "test" "$OUTPUT"
assert_output_contains "example: has execution_time metric" "execution_time" "$OUTPUT"
assert_output_contains "example: has readonly entries" "package.json" "$OUTPUT"

# ─── Test: Minimal config ───
echo ""
echo "--- minimal config ---"
TMPFILE=$(mktemp --suffix=.yaml)
cat > "$TMPFILE" <<'YAML'
gates:
  - name: test
    command: "echo ok"
    expect: exit_code_0
    optional: false

objectives:
  - name: score
    command: "echo 100"
    parse: "([0-9]+)"
    weight: 1.0
    direction: higher
YAML

OUTPUT=$(bash "$GATE_SCRIPT" parse-config --config "$TMPFILE" 2>&1)
assert_output_contains "minimal: has test gate" "test" "$OUTPUT"
assert_output_contains "minimal: has score objective" "score" "$OUTPUT"
rm -f "$TMPFILE"

# ─── Test: Multiple objectives ───
echo ""
echo "--- multiple objectives ---"
TMPFILE=$(mktemp --suffix=.yaml)
cat > "$TMPFILE" <<'YAML'
gates:
  - name: build
    command: "echo ok"
    expect: exit_code_0
    optional: false

objectives:
  - name: speed
    command: "echo 50"
    parse: "([0-9]+)"
    weight: 0.6
    direction: lower
  - name: memory
    command: "echo 200"
    parse: "([0-9]+)"
    weight: 0.4
    direction: lower
YAML

OUTPUT=$(bash "$GATE_SCRIPT" parse-config --config "$TMPFILE" 2>&1)
assert_output_contains "multi-obj: has speed" "speed" "$OUTPUT"
assert_output_contains "multi-obj: has memory" "memory" "$OUTPUT"
rm -f "$TMPFILE"

# ─── Test: Template configs generate valid YAML ───
echo ""
echo "--- template yaml blocks ---"
for template in "$PROJECT_DIR/templates/"*.md; do
    name=$(basename "$template" .md)
    # Extract YAML block from template
    YAML_BLOCK=$(sed -n '/^```yaml$/,/^```$/p' "$template" | sed '1d;$d' | head -30)
    if [[ -n "$YAML_BLOCK" ]]; then
        TMPFILE=$(mktemp --suffix=.yaml)
        echo "$YAML_BLOCK" > "$TMPFILE"
        OUTPUT=$(bash "$GATE_SCRIPT" parse-config --config "$TMPFILE" 2>&1 || true)
        TOTAL=$((TOTAL + 1))
        if echo "$OUTPUT" | grep -q "Gates\|Objectives"; then
            echo -e "${GREEN}PASS${NC} template $name: YAML is parseable"
            PASS=$((PASS + 1))
        else
            echo -e "${RED}FAIL${NC} template $name: YAML parse failed"
            FAIL=$((FAIL + 1))
        fi
        rm -f "$TMPFILE"
    fi
done

# ─── Test: Missing config file ───
echo ""
echo "--- error handling ---"
TOTAL=$((TOTAL + 1))
if bash "$GATE_SCRIPT" parse-config --config "/nonexistent/config.yaml" >/dev/null 2>&1; then
    echo -e "${RED}FAIL${NC} missing config should fail"
    FAIL=$((FAIL + 1))
else
    echo -e "${GREEN}PASS${NC} missing config correctly fails"
    PASS=$((PASS + 1))
fi

# ═══════════════════════════════════════════
echo ""
echo "═══════════════════════════════════════════"
echo " Results: $PASS passed, $FAIL failed, $TOTAL total"
echo "═══════════════════════════════════════════"

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
