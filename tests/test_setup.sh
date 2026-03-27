#!/usr/bin/env bash
# AutoCode setup.sh Unit Tests
# Usage: bash tests/test_setup.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SETUP_SCRIPT="$PROJECT_DIR/scripts/setup.sh"
GATE_SCRIPT="$PROJECT_DIR/scripts/gate.sh"
TEST_DIR=$(mktemp -d)
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
    git add -A 2>/dev/null || true
    git commit -q -m "init" --allow-empty
}

teardown() {
    rm -rf "$TEST_DIR"
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

assert_file_not_exists() {
    local desc="$1" file="$2"
    TOTAL=$((TOTAL + 1))
    if [[ ! -f "$file" ]]; then
        echo -e "${GREEN}PASS${NC} $desc"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}FAIL${NC} $desc (file should not exist: $file)"
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

# Source setup.sh to access detect_project_type directly
source "$SETUP_SCRIPT"

# ═══════════════════════════════════════════
echo "=== AutoCode setup.sh Tests ==="
echo ""

# ─── Test 1: Node.js Frontend Detection ───
echo "--- 1. Node.js frontend detection ---"
setup

cat > "$TEST_DIR/package.json" <<'JSON'
{
  "name": "my-app",
  "dependencies": {
    "react": "^18.0.0",
    "vite": "^5.0.0"
  }
}
JSON

result=$(detect_project_type "$TEST_DIR")
assert_eq "package.json with vite/react -> web-frontend" "web-frontend" "$result"

teardown

# ─── Test 2: Node.js Backend Detection ───
echo ""
echo "--- 2. Node.js backend detection ---"
setup

cat > "$TEST_DIR/package.json" <<'JSON'
{
  "name": "my-api",
  "dependencies": {
    "express": "^4.18.0"
  }
}
JSON

result=$(detect_project_type "$TEST_DIR")
assert_eq "package.json with express -> web-backend" "web-backend" "$result"

teardown

# ─── Test 3: Rust Detection ───
echo ""
echo "--- 3. Rust detection ---"
setup

cat > "$TEST_DIR/Cargo.toml" <<'TOML'
[package]
name = "my-crate"
version = "0.1.0"
TOML

result=$(detect_project_type "$TEST_DIR")
assert_eq "Cargo.toml -> rust" "rust" "$result"

teardown

# ─── Test 4: Go Detection ───
echo ""
echo "--- 4. Go detection ---"
setup

cat > "$TEST_DIR/go.mod" <<'MOD'
module example.com/myapp
go 1.21
MOD

result=$(detect_project_type "$TEST_DIR")
assert_eq "go.mod -> go" "go" "$result"

teardown

# ─── Test 5: Java Detection ───
echo ""
echo "--- 5. Java detection ---"
setup

cat > "$TEST_DIR/build.gradle" <<'GRADLE'
plugins {
    id 'java'
}
GRADLE

result=$(detect_project_type "$TEST_DIR")
assert_eq "build.gradle -> java" "java" "$result"

teardown

# ─── Test 6: Docker Detection ───
echo ""
echo "--- 6. Docker detection ---"
setup

cat > "$TEST_DIR/Dockerfile" <<'DOCKER'
FROM alpine:3.18
CMD ["echo", "hello"]
DOCKER

result=$(detect_project_type "$TEST_DIR")
assert_eq "Dockerfile -> docker" "docker" "$result"

teardown

# ─── Test 7: Python Detection ───
echo ""
echo "--- 7. Python detection ---"
setup

touch "$TEST_DIR/requirements.txt"

result=$(detect_project_type "$TEST_DIR")
assert_eq "requirements.txt -> python" "python" "$result"

teardown

# ─── Test 8: Custom (empty directory) ───
echo ""
echo "--- 8. Custom (empty directory) ---"
setup

result=$(detect_project_type "$TEST_DIR")
assert_eq "empty directory -> custom" "custom" "$result"

teardown

# ─── Test 9: Generated YAML is parseable ───
echo ""
echo "--- 9. Generated YAML is parseable ---"
setup

cat > "$TEST_DIR/Cargo.toml" <<'TOML'
[package]
name = "test"
TOML

bash "$SETUP_SCRIPT" --config "$TEST_DIR/.autocode.yaml" >/dev/null 2>&1

assert_file_exists "YAML file generated" "$TEST_DIR/.autocode.yaml"

# Verify it can be parsed by gate.sh parse-config
OUTPUT=$(bash "$GATE_SCRIPT" parse-config --config "$TEST_DIR/.autocode.yaml" 2>/dev/null)
TOTAL=$((TOTAL + 1))
if echo "$OUTPUT" | grep -q "Gates"; then
    echo -e "${GREEN}PASS${NC} Generated YAML is parseable by gate.sh parse-config"
    PASS=$((PASS + 1))
else
    echo -e "${RED}FAIL${NC} Generated YAML is not parseable (output: $OUTPUT)"
    FAIL=$((FAIL + 1))
fi

assert_contains "YAML has gates section" "$TEST_DIR/.autocode.yaml" "gates:"
assert_contains "YAML has objectives section" "$TEST_DIR/.autocode.yaml" "objectives:"
assert_contains "YAML has cargo build gate" "$TEST_DIR/.autocode.yaml" "cargo build"

teardown

# ─── Test 10: --dry-run does not create file ───
echo ""
echo "--- 10. --dry-run does not create file ---"
setup

cat > "$TEST_DIR/go.mod" <<'MOD'
module example.com/test
go 1.21
MOD

OUTPUT=$(bash "$SETUP_SCRIPT" --config "$TEST_DIR/.autocode.yaml" --dry-run 2>&1)

assert_file_not_exists "--dry-run does not create .autocode.yaml" "$TEST_DIR/.autocode.yaml"

TOTAL=$((TOTAL + 1))
if echo "$OUTPUT" | grep -q "dry-run"; then
    echo -e "${GREEN}PASS${NC} --dry-run outputs dry-run message"
    PASS=$((PASS + 1))
else
    echo -e "${RED}FAIL${NC} --dry-run should mention dry-run in output"
    FAIL=$((FAIL + 1))
fi

teardown

# ─── Test 11: Existing config is skipped ───
echo ""
echo "--- 11. Existing config is skipped ---"
setup

echo "# existing config" > "$TEST_DIR/.autocode.yaml"

bash "$SETUP_SCRIPT" --config "$TEST_DIR/.autocode.yaml" >/dev/null 2>&1

CONTENT=$(cat "$TEST_DIR/.autocode.yaml")
assert_eq "Existing config not overwritten" "# existing config" "$CONTENT"

teardown

# ─── Test 12: --force overwrites existing config ───
echo ""
echo "--- 12. --force overwrites existing config ---"
setup

echo "# old config" > "$TEST_DIR/.autocode.yaml"
cat > "$TEST_DIR/requirements.txt" <<'TXT'
flask==3.0
TXT

bash "$SETUP_SCRIPT" --config "$TEST_DIR/.autocode.yaml" --force >/dev/null 2>&1

assert_contains "--force overwrites with new content" "$TEST_DIR/.autocode.yaml" "python"

TOTAL=$((TOTAL + 1))
CONTENT=$(cat "$TEST_DIR/.autocode.yaml")
if echo "$CONTENT" | grep -q "# old config"; then
    echo -e "${RED}FAIL${NC} --force should replace old content"
    FAIL=$((FAIL + 1))
else
    echo -e "${GREEN}PASS${NC} --force replaced old content"
    PASS=$((PASS + 1))
fi

teardown

# ═══════════════════════════════════════════
echo ""
echo "==========================================="
echo " Results: $PASS passed, $FAIL failed, $TOTAL total"
echo "==========================================="

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
