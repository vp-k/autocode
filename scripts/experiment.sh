#!/usr/bin/env bash
# AutoCode Experiment Management Script
# Usage:
#   bash experiment.sh start   [--config .autocode.yaml] [--tag name]
#   bash experiment.sh commit  [--config .autocode.yaml] --message "msg"
#   bash experiment.sh discard [--config .autocode.yaml]
#   bash experiment.sh status  [--config .autocode.yaml]
set -euo pipefail

# ─── Source common library with guard ───
_COMMON_SH="$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
if [[ -f "$_COMMON_SH" ]]; then
    source "$_COMMON_SH"
else
    # Fallback definitions when common.sh is not yet available
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
    CONFIG_FILE=".autocode.yaml"
    LOG_DIR=".autocode/logs"
    RESULTS_FILE="results.tsv"
    JSONL_FILE="${LOG_DIR}/experiments.jsonl"
    MEMORY_FILE=".autocode/memory.md"
    log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
    log_ok()    { echo -e "${GREEN}[PASS]${NC} $*"; }
    log_fail()  { echo -e "${RED}[FAIL]${NC} $*" >&2; }
    log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
    now_iso()   { date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%S"; }
    json_escape() {
        local s="$1"
        s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; s="${s//$'\r'/\\r}"; s="${s//$'\t'/\\t}"
        echo -n "$s"
    }
    parse_yaml() {
        local yaml_file="$1" prefix="${2:-cfg}"
        [[ ! -f "$yaml_file" ]] && { log_fail "Config file not found: $yaml_file"; exit 2; }
        awk -v prefix="$prefix" -v SQ="'" '
        function clean(s) { sub(/#.*$/, "", s); gsub(/[[:space:]]+$/, "", s); gsub(/^[[:space:]]+/, "", s); gsub(/"/, "", s); gsub(SQ, "", s); return s }
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
fi

# ─── Fallback for STATE_FILE ───
STATE_FILE="${STATE_FILE:-.autocode/state.json}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── State JSON helpers (no jq) ───

# Read a top-level string/number value from state.json
# Usage: state_get "key"
state_get() {
    local key="$1"
    if [[ ! -f "$STATE_FILE" ]]; then
        echo ""
        return
    fi
    # Extract value for "key":value or "key":"value"
    grep -o "\"${key}\"[[:space:]]*:[[:space:]]*[^,}]*" "$STATE_FILE" 2>/dev/null \
        | head -1 \
        | sed 's/^[^:]*:[[:space:]]*//' \
        | sed 's/^"//;s/"$//' \
        | sed 's/[[:space:]]*$//'
}

# Set a top-level value in state.json
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
        quoted_value="\"$value\""
    fi

    # Use sed to replace the value in-place
    if grep -q "\"${key}\"" "$STATE_FILE" 2>/dev/null; then
        sed -i "s|\"${key}\"[[:space:]]*:[[:space:]]*[^,}]*|\"${key}\":${quoted_value}|g" "$STATE_FILE"
    fi
}

# ─── Commands ───

cmd_start() {
    local config="$1" tag="${2:-}"

    # 0. Ensure git repository exists
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        log_warn "Not a git repository. Initializing..."
        git init -q
        git add -A
        git commit -q -m "Initial commit (auto-created by autocode)" --allow-empty
        log_ok "Git repository initialized with initial commit"
    fi

    # 1. Check working tree is clean
    local status
    status=$(git status --porcelain 2>/dev/null) || true
    if [[ -n "$status" ]]; then
        log_warn "Working tree not clean. Auto-committing..."
        git add -A
        git commit -q -m "autocode: save uncommitted changes before experiment"
        log_ok "Uncommitted changes saved"
    fi

    # 2. Generate tag
    if [[ -z "$tag" ]]; then
        tag=$(date +%Y%m%d-%H%M)
    fi
    local branch="autocode/$tag"

    # 3. Create branch
    git checkout -b "$branch"
    log_ok "Created branch: $branch"

    # 4. Initialize environment
    bash "${SCRIPT_DIR}/gate.sh" init --config "$config"

    # 5. Create state.json
    mkdir -p "$(dirname "$STATE_FILE")"
    cat > "$STATE_FILE" <<EOF
{"branch":"${branch}","experiment_id":0,"baseline_score":null,"best_score":null,"best_commit":null,"direction":"lower"}
EOF
    log_ok "Created $STATE_FILE"

    # 6. Measure baseline
    log_info "Measuring baseline..."
    local measure_output
    measure_output=$(bash "${SCRIPT_DIR}/gate.sh" measure --config "$config" 2>/dev/null) || true

    # Extract _composite.score from measure output
    local baseline_score
    baseline_score=$(echo "$measure_output" | grep -o '"_composite":{[^}]*}' | grep -o '"score":[^,}]*' | sed 's/"score"://' | head -1)

    if [[ -n "$baseline_score" && "$baseline_score" != "null" ]]; then
        state_set "baseline_score" "$baseline_score" --number
        state_set "best_score" "$baseline_score" --number

        # Detect direction from config
        local direction="lower"
        local first_obj
        first_obj=$(awk -v SQ="'" '
        function clean(s) { sub(/#.*$/, "", s); gsub(/^[[:space:]]+/, "", s); gsub(/[[:space:]]+$/, "", s); gsub(/"/, "", s); gsub(SQ, "", s); return s }
        /^objectives:/ { in_obj=1; next }
        in_obj && /^[a-zA-Z]/ { exit }
        in_obj && /^[[:space:]]*direction:/ {
            dir=$0; sub(/.*direction:[[:space:]]*/, "", dir); dir=clean(dir)
            print dir; exit
        }
        ' "$config" 2>/dev/null)
        if [[ -n "$first_obj" ]]; then
            direction="$first_obj"
            state_set "direction" "$direction"
        fi

        log_ok "Baseline score: $baseline_score (direction: $direction)"

        # 7. Log baseline
        local commit_hash
        commit_hash=$(git rev-parse --short HEAD 2>/dev/null || echo "none")
        bash "${SCRIPT_DIR}/gate.sh" log --config "$config" \
            --commit "$commit_hash" --value "$baseline_score" --prev "$baseline_score" --delta "0" \
            --status "baseline" --description "Baseline measurement" \
            --strategy "" --experiment-id "0" --delta-pct "0" --cumulative-pct "0" \
            --direction "$direction"
    else
        log_warn "Could not measure baseline score"
    fi

    log_ok "Experiment started on branch: $branch"
}

cmd_commit() {
    local config="$1" message="${2:-}"

    # 1. Message is required
    if [[ -z "$message" ]]; then
        log_fail "--message is required"
        exit 1
    fi

    # 2. Read and increment experiment_id
    local exp_id
    exp_id=$(state_get "experiment_id")
    exp_id="${exp_id:-0}"
    exp_id=$((exp_id + 1))

    # 3. Changeset validation
    local max_files max_lines
    eval "$(parse_yaml "$config" cfg)" 2>/dev/null || true
    max_files="${cfg_changeset_max_files:-999}"
    max_lines="${cfg_changeset_max_lines:-9999}"

    # Stage if nothing staged
    local staged
    staged=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$staged" -eq 0 ]]; then
        git add -A
    fi

    # Parse file count and line count from staged changes
    local stat_output file_count line_count
    stat_output=$(git diff --cached --stat 2>/dev/null) || true

    # File count: count lines that are file entries (have |)
    file_count=$(echo "$stat_output" | grep '|' | wc -l | tr -d ' ')

    # Line count: sum insertions and deletions from --numstat
    line_count=$(git diff --cached --numstat 2>/dev/null | awk '{s+=$1+$2} END {print s+0}')

    if [[ "$file_count" -gt "$max_files" ]]; then
        log_fail "Changeset too large: $file_count files (max: $max_files)"
        exit 1
    fi
    if [[ "$line_count" -gt "$max_lines" ]]; then
        log_fail "Changeset too large: $line_count lines (max: $max_lines)"
        exit 1
    fi

    # 4. Check readonly
    bash "${SCRIPT_DIR}/gate.sh" check-readonly --config "$config"

    # 5. Commit
    git add -A
    git commit -m "autocode: $message"

    # 6. Update state
    state_set "experiment_id" "$exp_id" --number

    # 7. Output commit hash
    local commit_hash
    commit_hash=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    log_ok "Committed experiment #${exp_id}: $commit_hash"
    echo "$commit_hash"
}

cmd_discard() {
    git reset --hard HEAD~1
    log_ok "Discarded experiment"
}

cmd_status() {
    if [[ ! -f "$STATE_FILE" ]]; then
        log_fail "No active experiment (state.json not found)"
        exit 1
    fi

    local branch exp_id baseline best
    branch=$(state_get "branch")
    exp_id=$(state_get "experiment_id")
    baseline=$(state_get "baseline_score")
    best=$(state_get "best_score")

    echo "═══════════════════════════════════════════"
    echo " AutoCode Experiment Status"
    echo "═══════════════════════════════════════════"
    echo " Branch:      $branch"
    echo " Experiment:  #$exp_id"
    echo " Baseline:    $baseline"
    echo " Best:        $best"
    echo "═══════════════════════════════════════════"

    # Recent experiment logs
    if [[ -f "$JSONL_FILE" ]]; then
        echo ""
        echo "Recent experiments:"
        tail -5 "$JSONL_FILE" 2>/dev/null | while IFS= read -r line; do
            local status desc score
            status=$(echo "$line" | grep -o '"status":"[^"]*"' | head -1 | sed 's/"status":"//;s/"//')
            desc=$(echo "$line" | grep -o '"description":"[^"]*"' | head -1 | sed 's/"description":"//;s/"//')
            score=$(echo "$line" | grep -o '"metric_value":[^,}]*' | head -1 | sed 's/"metric_value"://')
            echo "  [$status] $desc (score: $score)"
        done
    fi

    # Recent git log
    echo ""
    echo "Recent commits:"
    git log --oneline -5 2>/dev/null || echo "  (no commits)"
}

# ─── Main ───
main() {
    local cmd="${1:-help}"
    shift || true

    local config="$CONFIG_FILE"
    local tag=""
    local message=""
    local remaining_args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config) config="$2"; shift 2 ;;
            --tag)    tag="$2"; shift 2 ;;
            --message) message="$2"; shift 2 ;;
            *) remaining_args+=("$1"); shift ;;
        esac
    done

    case "$cmd" in
        start)
            cmd_start "$config" "$tag"
            ;;
        commit)
            cmd_commit "$config" "$message"
            ;;
        discard)
            cmd_discard
            ;;
        status)
            cmd_status
            ;;
        help|--help|-h)
            echo "AutoCode Experiment Script"
            echo ""
            echo "Usage: bash experiment.sh <command> [options]"
            echo ""
            echo "Commands:"
            echo "  start   [--config yaml] [--tag name]     Start new experiment"
            echo "  commit  [--config yaml] --message \"msg\"  Commit experiment"
            echo "  discard [--config yaml]                  Discard last experiment"
            echo "  status  [--config yaml]                  Show experiment status"
            ;;
        *)
            log_fail "Unknown command: $cmd"
            exit 2
            ;;
    esac
}

# Only run main if not being sourced (for testing)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
