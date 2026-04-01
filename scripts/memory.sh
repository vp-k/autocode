#!/usr/bin/env bash
# AutoCode Memory Auto-Update Script
# Usage: bash memory.sh update [--config .autocode.yaml]
set -euo pipefail

# ─── Source common library ───
_COMMON_SH="$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
if [[ -f "$_COMMON_SH" ]]; then
    source "$_COMMON_SH"
else
    echo "[FAIL] common.sh not found: $_COMMON_SH" >&2
    exit 2
fi

# ─── Commands ───

cmd_update() {
    local config="${1:-$CONFIG_FILE}"

    # Ensure directories exist
    mkdir -p "$(dirname "$MEMORY_FILE")"

    # 1. Read recent experiments from JSONL (last 10)
    local recent_lines=""
    if [[ -f "$JSONL_FILE" ]]; then
        recent_lines=$(tail -10 "$JSONL_FILE" 2>/dev/null) || true
    fi

    # 2. Collect "What Worked" (keep items)
    local what_worked=""
    if [[ -n "$recent_lines" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local status desc delta_pct
            status=$(jsonl_field "$line" "status")
            if [[ "$status" == "keep" ]]; then
                desc=$(jsonl_field "$line" "description")
                desc="${desc:-(no description)}"
                delta_pct=$(jsonl_field "$line" "delta_pct")
                what_worked="${what_worked}- ${desc} (delta: ${delta_pct}%)\n"
            fi
        done <<< "$recent_lines"
    fi
    if [[ -z "$what_worked" ]]; then
        what_worked="(no successful experiments yet)\n"
    fi

    # 3. Collect "What Failed" (discard/crash/gate_fail items)
    local what_failed=""
    if [[ -n "$recent_lines" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local status desc
            status=$(jsonl_field "$line" "status")
            if [[ "$status" == "discard" || "$status" == "crash" || "$status" == "gate_fail" ]]; then
                desc=$(jsonl_field "$line" "description")
                desc="${desc:-(no description)}"
                what_failed="${what_failed}- ${desc} (${status})\n"
            fi
        done <<< "$recent_lines"
    fi
    if [[ -z "$what_failed" ]]; then
        what_failed="(no failed experiments yet)\n"
    fi

    # 4. Current Best from state.json
    local best_score best_commit
    best_score=$(state_get "best_score")
    best_commit=$(state_get "best_commit")
    best_score="${best_score:-unknown}"
    best_commit="${best_commit:-none}"

    # 5. Collect used strategies and compute unexplored
    local all_strategies="algorithmic micro structural config elimination"
    local used_strategies=""
    if [[ -n "$recent_lines" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local strategy
            strategy=$(jsonl_field "$line" "strategy")
            if [[ -n "$strategy" ]]; then
                used_strategies="${used_strategies} ${strategy}"
            fi
        done <<< "$recent_lines"
    fi

    local unexplored=""
    for s in $all_strategies; do
        if ! echo "$used_strategies" | grep -qw "$s"; then
            local display_name
            case "$s" in
                algorithmic) display_name="Algorithmic changes" ;;
                micro)       display_name="Micro-optimizations" ;;
                structural)  display_name="Structural refactoring" ;;
                config)      display_name="Configuration tuning" ;;
                elimination) display_name="Code elimination" ;;
                *)           display_name="$s" ;;
            esac
            unexplored="${unexplored}- ${display_name}\n"
        fi
    done
    if [[ -z "$unexplored" ]]; then
        unexplored="(all strategies explored)\n"
    fi

    # Preserve manual notes section if exists
    local manual_notes=""
    if [[ -f "$MEMORY_FILE" ]]; then
        manual_notes=$(awk '/^### Manual Notes/,0' "$MEMORY_FILE" 2>/dev/null) || true
    fi

    # 6. Write memory.md
    cat > "$MEMORY_FILE" <<EOF
## Experiment Memory

### What Worked
$(echo -e "$what_worked")
### What Failed
$(echo -e "$what_failed")
### Current Best
- Metric: ${best_score}
- Commit: ${best_commit}

### Unexplored Directions
$(echo -e "$unexplored")
EOF

    # Re-append manual notes
    if [[ -n "$manual_notes" ]]; then
        echo "" >> "$MEMORY_FILE"
        echo "$manual_notes" >> "$MEMORY_FILE"
    fi

    log_ok "Updated $MEMORY_FILE"
}

# ─── Main ───
main() {
    local cmd="${1:-help}"
    shift || true

    local config="$CONFIG_FILE"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config) config="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    case "$cmd" in
        update)
            cmd_update "$config"
            ;;
        help|--help|-h)
            echo "AutoCode Memory Script"
            echo ""
            echo "Usage: bash memory.sh update [--config .autocode.yaml]"
            echo ""
            echo "Regenerates .autocode/memory.md from experiment logs."
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
