#!/usr/bin/env bash
# AutoCode Quality Gate & Metric Measurement Script
# Usage:
#   bash gate.sh gates   --config .autocode.yaml   # Run hard gates
#   bash gate.sh measure --config .autocode.yaml   # Measure soft metrics
#   bash gate.sh init    --config .autocode.yaml   # Initialize experiment environment
#   bash gate.sh parse-config --config .autocode.yaml  # Dump parsed config as JSON
set -euo pipefail

# ─── Load common library ───
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

# ─── Commands ───

cmd_init() {
    local config_file="${1:-$CONFIG_FILE}"
    log_info "Initializing AutoCode environment..."

    # Create directories
    mkdir -p "$LOG_DIR"
    mkdir -p .autocode

    # Initialize results.tsv
    if [[ ! -f "$RESULTS_FILE" ]]; then
        echo -e "commit\tmetric_value\tprev_value\tdelta\tstatus\tdescription\ttimestamp" > "$RESULTS_FILE"
        log_ok "Created $RESULTS_FILE"
    fi

    # Initialize JSONL log
    if [[ ! -f "$JSONL_FILE" ]]; then
        touch "$JSONL_FILE"
        log_ok "Created $JSONL_FILE"
    fi

    # Initialize experiment memory
    if [[ ! -f "$MEMORY_FILE" ]]; then
        cat > "$MEMORY_FILE" <<'MEMORY_EOF'
## Experiment Memory

### What Worked
(no experiments yet)

### What Failed
(no experiments yet)

### Current Best
- Metric: (baseline not measured)
- Commit: (none)

### Unexplored Directions
- Algorithmic changes
- Micro-optimizations
- Structural refactoring
- Configuration tuning
- Code elimination
MEMORY_EOF
        log_ok "Created $MEMORY_FILE"
    fi

    log_ok "AutoCode environment initialized"
}

cmd_gates() {
    local config_file="${1:-$CONFIG_FILE}"
    local all_passed=true
    local gate_results=""

    log_info "Running hard gates..."

    while IFS=$'\t' read -r name cmd expect optional; do
        [[ -z "$name" || -z "$cmd" ]] && continue

        log_info "Gate [$name]: $cmd"

        local output exit_code=0
        output=$(run_cmd "$cmd") || exit_code=$?

        local passed=false
        # Currently only exit_code_0 is supported; extensible for future expect types
        [[ $exit_code -eq 0 ]] && passed=true

        if $passed; then
            log_ok "Gate [$name]: PASS"
            gate_results="${gate_results}${name}=pass,"
        else
            if [[ "$optional" == "true" ]]; then
                log_warn "Gate [$name]: FAIL (optional, skipping)"
                gate_results="${gate_results}${name}=skip,"
            else
                log_fail "Gate [$name]: FAIL (exit code: $exit_code)"
                log_fail "Output: ${output:0:500}"
                gate_results="${gate_results}${name}=fail,"
                all_passed=false
            fi
        fi
    done < <(parse_gates "$config_file")

    # Output gate results as JSON
    local json_results="{"
    IFS=',' read -ra pairs <<< "$gate_results"
    local first=true
    for pair in "${pairs[@]}"; do
        [[ -z "$pair" ]] && continue
        local key="${pair%%=*}"
        local val="${pair##*=}"
        $first || json_results+=","
        json_results+="\"$key\":\"$val\""
        first=false
    done
    json_results+="}"

    echo "$json_results"

    if $all_passed; then
        return 0
    else
        return 1
    fi
}

cmd_measure() {
    local config_file="${1:-$CONFIG_FILE}"
    local total_score=0
    local total_weight=0
    local metrics_json="{"
    local first=true

    log_info "Measuring soft metrics..."

    while IFS=$'\t' read -r name cmd parse_regex weight direction; do
        [[ -z "$name" || -z "$cmd" ]] && continue

        log_info "Metric [$name]: $cmd"

        local output exit_code=0
        output=$(run_cmd "$cmd") || exit_code=$?

        if [[ $exit_code -ne 0 ]]; then
            log_warn "Metric [$name]: command failed (exit code: $exit_code)"
            $first || metrics_json+=","
            metrics_json+="\"$name\":{\"value\":null,\"error\":\"command_failed\"}"
            first=false
            continue
        fi

        # Parse metric value
        local value=""
        if [[ -n "$parse_regex" ]]; then
            value=$(echo "$output" | grep -oP "$parse_regex" | head -1 2>/dev/null || echo "")
            # Try to extract the first number from the match
            if [[ -n "$value" ]]; then
                value=$(echo "$value" | grep -oP '[0-9]+\.?[0-9]*' | head -1 2>/dev/null || echo "$value")
            fi
        else
            # Try to extract any number from output
            value=$(echo "$output" | grep -oP '[0-9]+\.?[0-9]*' | tail -1 2>/dev/null || echo "")
        fi

        if [[ -z "$value" ]]; then
            log_warn "Metric [$name]: could not parse value from output"
            $first || metrics_json+=","
            metrics_json+="\"$name\":{\"value\":null,\"error\":\"parse_failed\"}"
            first=false
            continue
        fi

        log_ok "Metric [$name]: $value (weight=$weight, direction=$direction)"

        # Compute normalized value, weighted contribution, and running totals in a single awk call
        read -r total_score total_weight < <(
            awk -v val="$value" -v w="$weight" -v dir="$direction" \
                -v ts="$total_score" -v tw="$total_weight" '
            BEGIN {
                nv = (dir == "lower") ? -val : val
                printf "%.6f %.6f\n", ts + (nv * w), tw + w
            }'
        )

        $first || metrics_json+=","
        metrics_json+="\"$name\":{\"value\":$value,\"weight\":$weight,\"direction\":\"$direction\"}"
        first=false

    done < <(parse_objectives "$config_file")

    # Calculate composite score
    local composite=0
    if (( $(awk "BEGIN {print ($total_weight > 0)}" ) )); then
        composite=$(awk "BEGIN {printf \"%.6f\", $total_score / $total_weight}")
    fi

    metrics_json+=",\"_composite\":{\"score\":$composite,\"total_weight\":$total_weight}"
    metrics_json+="}"

    echo "$metrics_json"
}

cmd_log() {
    # Append a result to both TSV and JSONL
    # Usage: gate.sh log --config <yaml> --commit <hash> --value <n> --prev <n> --delta <n>
    #        --status <keep|discard|crash|gate_fail|parse_error> --description <text>
    #        --strategy <type> --changed-files <f1,f2> --changed-lines <n>
    #        --gate-results <json> --experiment-id <n> --delta-pct <n>
    #        --cumulative-pct <n>

    local commit="" value="" prev="" delta="" status="" desc="" strategy=""
    local changed_files="" changed_lines="0" gate_json="{}" exp_id="0"
    local delta_pct="0" cumulative_pct="0" config_file="$CONFIG_FILE"
    local direction=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config) config_file="$2"; shift 2 ;;
            --commit) commit="$2"; shift 2 ;;
            --value) value="$2"; shift 2 ;;
            --prev) prev="$2"; shift 2 ;;
            --delta) delta="$2"; shift 2 ;;
            --status) status="$2"; shift 2 ;;
            --description) desc="$2"; shift 2 ;;
            --strategy) strategy="$2"; shift 2 ;;
            --changed-files) changed_files="$2"; shift 2 ;;
            --changed-lines) changed_lines="$2"; shift 2 ;;
            --gate-results) gate_json="$2"; shift 2 ;;
            --experiment-id) exp_id="$2"; shift 2 ;;
            --delta-pct) delta_pct="$2"; shift 2 ;;
            --cumulative-pct) cumulative_pct="$2"; shift 2 ;;
            --direction) direction="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local ts
    ts=$(now_iso)

    local safe_desc safe_commit safe_strategy safe_metric_name
    safe_desc=$(json_escape "$desc")
    safe_commit=$(json_escape "$commit")
    safe_strategy=$(json_escape "$strategy")

    # Append to TSV (tab-escaped description)
    local tsv_desc="${desc//$'\t'/ }"
    echo -e "${commit}\t${value}\t${prev}\t${delta}\t${status}\t${tsv_desc}\t${ts}" >> "$RESULTS_FILE"

    # Build changed_files JSON array
    local files_json="[]"
    if [[ -n "$changed_files" ]]; then
        files_json=$(echo "$changed_files" | awk -F',' '{
            printf "["
            for(i=1;i<=NF;i++) {
                if(i>1) printf ","
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i)
                printf "\"%s\"", $i
            }
            printf "]"
        }')
    fi

    # Get metric name from config (using parse_objectives, not parse_yaml)
    local metric_name="metric"
    local first_obj
    first_obj=$(parse_objectives "$config_file" 2>/dev/null | head -1)
    if [[ -n "$first_obj" ]]; then
        metric_name=$(echo "$first_obj" | cut -d$'\t' -f1)
        metric_name="${metric_name:-metric}"
        # Get direction from config if not explicitly passed via --direction
        if [[ -z "$direction" ]]; then
            local cfg_dir
            cfg_dir=$(echo "$first_obj" | cut -d$'\t' -f5)
            direction="${cfg_dir:-lower}"
        fi
    fi
    safe_metric_name=$(json_escape "$metric_name")
    direction="${direction:-lower}"

    cat >> "$JSONL_FILE" <<JSONL_EOF
{"experiment_id":${exp_id},"commit":"${safe_commit}","metric_name":"${safe_metric_name}","metric_value":${value:-null},"prev_value":${prev:-null},"delta":${delta:-0},"delta_pct":${delta_pct},"status":"${status}","description":"${safe_desc}","strategy":"${safe_strategy}","changed_files":${files_json},"changed_lines":${changed_lines},"gate_results":${gate_json},"timestamp":"${ts}","cumulative_improvement_pct":${cumulative_pct},"metric_direction":"${direction}"}
JSONL_EOF

    log_ok "Logged experiment #${exp_id}: ${status} (${desc})"
}

cmd_parse_config() {
    local config_file="${1:-$CONFIG_FILE}"

    echo "=== Gates ==="
    parse_gates "$config_file"
    echo ""
    echo "=== Objectives ==="
    parse_objectives "$config_file"
    echo ""
    echo "=== Readonly ==="
    parse_readonly "$config_file"
}

cmd_check_readonly() {
    # Check if any modified files match readonly patterns
    local config_file="${1:-$CONFIG_FILE}"
    local modified_files="${2:-}"

    if [[ -z "$modified_files" ]]; then
        modified_files=$(git diff --name-only HEAD~1 HEAD 2>/dev/null || echo "")
    fi

    local violations=""
    while read -r pattern; do
        [[ -z "$pattern" ]] && continue
        while read -r file; do
            [[ -z "$file" ]] && continue
            # Simple glob matching
            if [[ "$file" == $pattern ]]; then
                violations="${violations}${file} (matches readonly: ${pattern})\n"
            fi
        done <<< "$modified_files"
    done < <(parse_readonly "$config_file")

    if [[ -n "$violations" ]]; then
        log_fail "Readonly violations detected:"
        echo -e "$violations" >&2
        return 1
    fi

    log_ok "No readonly violations"
    return 0
}

cmd_summary() {
    local config_file="${1:-$CONFIG_FILE}"

    if [[ ! -f "$JSONL_FILE" ]]; then
        log_warn "No experiment logs found"
        return 0
    fi

    local total kept discarded crashed gate_failed
    total=$(wc -l < "$JSONL_FILE" | tr -d ' ')
    kept=$(grep -c '"status":"keep"' "$JSONL_FILE" 2>/dev/null || echo "0")
    discarded=$(grep -c '"status":"discard"' "$JSONL_FILE" 2>/dev/null || echo "0")
    crashed=$(grep -c '"status":"crash"' "$JSONL_FILE" 2>/dev/null || echo "0")
    gate_failed=$(grep -c '"status":"gate_fail"' "$JSONL_FILE" 2>/dev/null || echo "0")

    local keep_rate=0
    if [[ $total -gt 0 ]]; then
        keep_rate=$(awk "BEGIN {printf \"%.1f\", $kept / $total * 100}")
    fi

    echo "═══════════════════════════════════════════"
    echo " AutoCode Summary"
    echo "═══════════════════════════════════════════"
    echo " Total:       $total experiments"
    echo " Kept:        $kept (${keep_rate}%)"
    echo " Discarded:   $discarded"
    echo " Gate Failed: $gate_failed"
    echo " Crashed:     $crashed"

    # Best result (respects metric_direction from JSONL)
    if command -v jq >/dev/null 2>&1 && [[ $kept -gt 0 ]]; then
        local direction best
        direction=$(grep -m1 '"metric_direction"' "$JSONL_FILE" | jq -r '.metric_direction // "lower"' 2>/dev/null || echo "lower")
        if [[ "$direction" == "higher" ]]; then
            best=$(grep '"status":"keep"' "$JSONL_FILE" | jq -s 'sort_by(.metric_value) | reverse | .[0]' 2>/dev/null || echo "")
        else
            best=$(grep '"status":"keep"' "$JSONL_FILE" | jq -s 'sort_by(.metric_value) | .[0]' 2>/dev/null || echo "")
        fi
        if [[ -n "$best" && "$best" != "null" ]]; then
            local best_val best_commit best_desc
            best_val=$(echo "$best" | jq -r '.metric_value' 2>/dev/null || echo "?")
            best_commit=$(echo "$best" | jq -r '.commit' 2>/dev/null || echo "?")
            best_desc=$(echo "$best" | jq -r '.description' 2>/dev/null || echo "?")
            echo " Best:        $best_val ($best_desc)"
            echo " Commit:      $best_commit"
        fi
    fi

    echo "═══════════════════════════════════════════"
}

# ─── Main ───
main() {
    local cmd="${1:-help}"
    shift || true

    # Parse --config flag
    local config="$CONFIG_FILE"
    local remaining_args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config) config="$2"; shift 2 ;;
            *) remaining_args+=("$1"); shift ;;
        esac
    done

    case "$cmd" in
        init)
            cmd_init "$config"
            ;;
        gates)
            cmd_gates "$config"
            ;;
        measure)
            cmd_measure "$config"
            ;;
        log)
            cmd_log --config "$config" "${remaining_args[@]}"
            ;;
        parse-config)
            cmd_parse_config "$config"
            ;;
        check-readonly)
            cmd_check_readonly "$config" "${remaining_args[0]:-}"
            ;;
        summary)
            cmd_summary "$config"
            ;;
        help|--help|-h)
            echo "AutoCode Gate Script"
            echo ""
            echo "Usage: bash gate.sh <command> [--config .autocode.yaml]"
            echo ""
            echo "Commands:"
            echo "  init           Initialize experiment environment"
            echo "  gates          Run hard gates (build/test/lint)"
            echo "  measure        Measure soft metrics"
            echo "  log            Record experiment result"
            echo "  parse-config   Show parsed configuration"
            echo "  check-readonly Check for readonly file violations"
            echo "  summary        Show experiment summary"
            echo "  help           Show this help"
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
