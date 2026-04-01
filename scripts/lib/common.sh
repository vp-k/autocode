#!/usr/bin/env bash
# AutoCode Common Library — sourced by gate.sh, experiment.sh, judge.sh, memory.sh, setup.sh
# Do not execute directly.
[[ -n "${_AUTOCODE_COMMON_LOADED:-}" ]] && return 0
_AUTOCODE_COMMON_LOADED=1

# ─── Colors ───
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ─── Defaults ───
CONFIG_FILE=".autocode.yaml"
LOG_DIR=".autocode/logs"
RESULTS_FILE="results.tsv"
JSONL_FILE="${LOG_DIR}/experiments.jsonl"
MEMORY_FILE=".autocode/memory.md"
STATE_FILE=".autocode/state.json"

# ─── Helpers ───
log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[PASS]${NC} $*"; }
log_fail()  { echo -e "${RED}[FAIL]${NC} $*" >&2; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
now_iso()   { date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%S"; }

# ─── JSON Escape ───
# Escapes special characters in a string for safe JSON embedding.
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"   # backslash
    s="${s//\"/\\\"}"   # double quote
    s="${s//$'\n'/\\n}" # newline
    s="${s//$'\r'/\\r}" # carriage return
    s="${s//$'\t'/\\t}" # tab
    echo -n "$s"
}

# ─── State JSON helpers (no jq) ───
STATE_FILE="${STATE_FILE:-.autocode/state.json}"

# Read a top-level string/number value from state.json
# Usage: state_get "key"
state_get() {
    local key="$1"
    if [[ ! -f "$STATE_FILE" ]]; then
        echo ""
        return
    fi
    local raw
    raw=$(grep -o "\"${key}\"[[:space:]]*:[[:space:]]*[^,}]*" "$STATE_FILE" 2>/dev/null | head -1) || true
    if [[ -n "$raw" ]]; then
        echo "$raw" | sed 's/^[^:]*:[[:space:]]*//' | sed 's/^"//;s/"$//' | sed 's/[[:space:]]*$//'
    else
        echo ""
    fi
}

# Set a top-level value in state.json
# Uses awk for safe literal replacement (no sed injection risk)
# Usage: state_set "key" "value" [--number]
state_set() {
    local key="$1" value="$2" is_number="${3:-}"
    if [[ ! -f "$STATE_FILE" ]]; then
        log_fail "State file not found: $STATE_FILE"
        return 1
    fi

    local quoted_value
    if [[ "$is_number" == "--number" ]] || [[ "$value" == "null" ]]; then
        quoted_value="$value"
    else
        quoted_value="\"$(json_escape "$value")\""
    fi

    local tmp="${STATE_FILE}.tmp.$$"
    # Use ENVIRON to pass values safely (avoids awk -v backslash interpretation)
    AUTOCODE_AWK_KEY="\"${key}\"" AUTOCODE_AWK_VAL="${quoted_value}" \
    awk '{
        qkey = ENVIRON["AUTOCODE_AWK_KEY"]
        newval = ENVIRON["AUTOCODE_AWK_VAL"]
        if (index($0, qkey":") > 0 || index($0, qkey" :") > 0) {
            match($0, qkey"[[:space:]]*:[[:space:]]*")
            pre = substr($0, 1, RSTART + RLENGTH - 1)
            rest = substr($0, RSTART + RLENGTH)
            sub(/^[^,}]*/, "", rest)
            print pre newval rest
        } else {
            print
        }
    }' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

# ─── Extract field from a JSONL line (no jq) ───
jsonl_field() {
    local line="$1" field="$2"
    local raw
    raw=$(echo "$line" | grep -o "\"${field}\"[[:space:]]*:[[:space:]]*[^,}]*" | head -1) || true
    if [[ -n "$raw" ]]; then
        echo "$raw" | sed 's/^[^:]*:[[:space:]]*//' | sed 's/^"//;s/"$//'
    else
        echo ""
    fi
}

# ─── Safe config value extraction (no eval) ───
# Usage: config_get "config_file" "key" "default"
config_get() {
    local config="$1" key="$2" default="${3:-}"
    local val
    val=$(parse_yaml "$config" cfg 2>/dev/null | grep "^cfg_${key}=" | head -1 | sed 's/^[^=]*="//' | sed 's/"$//')
    echo "${val:-$default}"
}

# ─── YAML Parser (minimal, no external deps) ───
# Parses simple YAML into shell variables. Handles:
#   key: value  →  cfg_key="value"
#   - item      →  array elements
# For nested structures, uses _ separator: parent_child="value"
parse_yaml() {
    local yaml_file="$1"
    local prefix="${2:-cfg}"

    if [[ ! -f "$yaml_file" ]]; then
        log_fail "Config file not found: $yaml_file"
        exit 2
    fi

    # Use a simple awk-based parser for flat and one-level-nested YAML
    awk -v prefix="$prefix" '
    function clean(s) {
        sub(/#.*$/, "", s); gsub(/[[:space:]]+$/, "", s); gsub(/^[[:space:]]+/, "", s)
        if (s ~ /^".*"$/) { s = substr(s, 2, length(s)-2) }
        else if (s ~ /^'\''.*'\''$/) { s = substr(s, 2, length(s)-2) }
        return s
    }
    BEGIN { section = "" }
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    /^[a-zA-Z_][a-zA-Z0-9_]*:/ {
        key = $0; sub(/:.*/, "", key); gsub(/[[:space:]]/, "", key)
        val = $0; sub(/^[^:]*:[[:space:]]*/, "", val); val = clean(val)
        if (val == "" || val ~ /^[|>]/) { section = key; next }
        printf "%s_%s=\"%s\"\n", prefix, key, val
        section = ""
    }
    /^[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*:/ && section != "" {
        key = $0; sub(/:.*/, "", key); gsub(/[[:space:]]/, "", key)
        val = $0; sub(/^[^:]*:[[:space:]]*/, "", val); val = clean(val)
        printf "%s_%s_%s=\"%s\"\n", prefix, section, key, val
    }
    ' "$yaml_file"
}

# ─── Parse gate entries from YAML ───
# Returns tab-separated: name\tcommand\texpect\toptional
parse_gates() {
    local config_file="${1:-$CONFIG_FILE}"

    awk '
    function clean(s) {
        sub(/#.*$/, "", s); gsub(/^[[:space:]]+/, "", s); gsub(/[[:space:]]+$/, "", s)
        if (s ~ /^".*"$/) { s = substr(s, 2, length(s)-2) }
        else if (s ~ /^'\''.*'\''$/) { s = substr(s, 2, length(s)-2) }
        return s
    }
    /^gates:/ { in_gates=1; next }
    in_gates && /^[a-zA-Z]/ { exit }
    in_gates && /^[[:space:]]*- name:/ {
        if (name != "" && cmd != "") printf "%s\t%s\t%s\t%s\n", name, cmd, xpect, opt
        name=$0; sub(/.*name:[[:space:]]*/, "", name); name=clean(name)
        cmd=""; xpect="exit_code_0"; opt="false"
    }
    in_gates && /^[[:space:]]*command:/ {
        cmd=$0; sub(/.*command:[[:space:]]*/, "", cmd); cmd=clean(cmd)
    }
    in_gates && /^[[:space:]]*expect:/ {
        xpect=$0; sub(/.*expect:[[:space:]]*/, "", xpect); xpect=clean(xpect)
    }
    in_gates && /^[[:space:]]*optional:/ {
        opt=$0; sub(/.*optional:[[:space:]]*/, "", opt); opt=clean(opt)
    }
    END {
        if (in_gates && name != "" && cmd != "") printf "%s\t%s\t%s\t%s\n", name, cmd, xpect, opt
    }
    ' "$config_file"
}

# ─── Parse objective entries from YAML ───
# Returns tab-separated: name\tcommand\tparse_regex\tweight\tdirection
parse_objectives() {
    local config_file="${1:-$CONFIG_FILE}"

    awk '
    function clean(s) {
        sub(/#.*$/, "", s); gsub(/^[[:space:]]+/, "", s); gsub(/[[:space:]]+$/, "", s)
        if (s ~ /^".*"$/) { s = substr(s, 2, length(s)-2) }
        else if (s ~ /^'\''.*'\''$/) { s = substr(s, 2, length(s)-2) }
        return s
    }
    /^objectives:/ { in_obj=1; next }
    in_obj && /^[a-zA-Z]/ { exit }
    in_obj && /^[[:space:]]*- name:/ {
        if (name != "" && cmd != "") printf "%s\t%s\t%s\t%s\t%s\n", name, cmd, preg, weight, dir
        name=$0; sub(/.*name:[[:space:]]*/, "", name); name=clean(name)
        cmd=""; preg=""; weight="1.0"; dir="lower"
    }
    in_obj && /^[[:space:]]*command:/ {
        cmd=$0; sub(/.*command:[[:space:]]*/, "", cmd); cmd=clean(cmd)
    }
    in_obj && /^[[:space:]]*parse:/ {
        preg=$0; sub(/.*parse:[[:space:]]*/, "", preg); preg=clean(preg)
    }
    in_obj && /^[[:space:]]*weight:/ {
        weight=$0; sub(/.*weight:[[:space:]]*/, "", weight); weight=clean(weight)
    }
    in_obj && /^[[:space:]]*direction:/ {
        dir=$0; sub(/.*direction:[[:space:]]*/, "", dir); dir=clean(dir)
    }
    END {
        if (in_obj && name != "" && cmd != "") printf "%s\t%s\t%s\t%s\t%s\n", name, cmd, preg, weight, dir
    }
    ' "$config_file"
}

# ─── Parse readonly patterns from YAML ───
parse_readonly() {
    local config_file="${1:-$CONFIG_FILE}"
    awk '
    function clean(s) {
        sub(/#.*$/, "", s); gsub(/^[[:space:]]+/, "", s); gsub(/[[:space:]]+$/, "", s)
        if (s ~ /^".*"$/) { s = substr(s, 2, length(s)-2) }
        else if (s ~ /^'\''.*'\''$/) { s = substr(s, 2, length(s)-2) }
        return s
    }
    /^readonly:/ { in_ro=1; next }
    in_ro && /^[a-zA-Z]/ { exit }
    in_ro && /^[[:space:]]*-/ {
        val=$0; sub(/^[[:space:]]*-[[:space:]]*/, "", val); val=clean(val)
        if (val != "") print val
    }
    ' "$config_file"
}

# ─── Safe Command Execution ───
# Runs a command string in a subshell (bash -c) instead of eval.
# Blocks known dangerous patterns to mitigate command injection from untrusted .autocode.yaml.
# NOTE: Blocklist approach is inherently incomplete — defense-in-depth, not a guarantee.
BLOCKED_PATTERNS='(rm[[:space:]]+-rf[[:space:]]+/|curl.*\|[[:space:]]*(ba)?sh|wget.*\|[[:space:]]*(ba)?sh|mkfs|dd[[:space:]]+if=|>[[:space:]]*/dev/sd|sudo[[:space:]]|chmod[[:space:]]+777|chmod[[:space:]]+\+s|>[[:space:]]*/etc/|:\(\)\{[[:space:]]*:\|:)'

run_cmd() {
    local cmd="$1" max_time="${2:-300}"
    if [[ "$cmd" =~ $BLOCKED_PATTERNS ]]; then
        log_fail "Blocked dangerous command pattern: $cmd"
        return 126
    fi
    if command -v timeout >/dev/null 2>&1; then
        timeout "$max_time" bash -c "$cmd" 2>&1
    else
        bash -c "$cmd" 2>&1
    fi
}
