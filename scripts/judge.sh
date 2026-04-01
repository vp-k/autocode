#!/usr/bin/env bash
# AutoCode Automatic Judgment Script
# Usage: bash judge.sh --config .autocode.yaml --current '{"_composite":{"score":-50.2}}'
# Exit: 0=keep, 1=discard
set -euo pipefail

# ─── Source common library ───
_COMMON_SH="$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
if [[ -f "$_COMMON_SH" ]]; then
    source "$_COMMON_SH"
else
    echo "[FAIL] common.sh not found: $_COMMON_SH" >&2
    exit 2
fi

# ─── Main ───
main() {
    local config="$CONFIG_FILE"
    local current_json=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config)  config="$2"; shift 2 ;;
            --current) current_json="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$current_json" ]]; then
        log_fail "--current argument is required"
        exit 2
    fi

    # 1. Extract _composite.score from --current JSON
    local current_score
    current_score=$(echo "$current_json" | grep -o '"score"[[:space:]]*:[[:space:]]*[-0-9eE.+]*' | head -1 | sed 's/.*:[[:space:]]*//')

    if [[ -z "$current_score" ]]; then
        log_fail "Could not parse score from --current"
        exit 2
    fi

    # 2. Read state
    local best_score direction baseline_score
    best_score=$(state_get "best_score")
    direction=$(state_get "direction")
    baseline_score=$(state_get "baseline_score")
    direction="${direction:-lower}"

    # 3. If baseline_score is null → this is the baseline
    if [[ "$baseline_score" == "null" || -z "$baseline_score" ]]; then
        state_set "baseline_score" "$current_score" --number
        state_set "best_score" "$current_score" --number
        local commit_hash
        commit_hash=$(git rev-parse --short HEAD 2>/dev/null || echo "none")
        state_set "best_commit" "$commit_hash"

        echo "{\"verdict\":\"keep\",\"current_score\":${current_score},\"best_score\":${current_score},\"delta\":0,\"delta_pct\":0}"
        log_ok "Baseline established: $current_score"
        exit 0
    fi

    # 4. Compare scores using awk
    # NOTE: gate.sh already normalizes composite scores by direction
    #   (direction=lower → negated, so higher composite = better in all cases).
    #   Therefore, always use current > best here. Do NOT re-apply direction.
    local verdict delta delta_pct
    read -r verdict delta delta_pct < <(
        awk -v current="$current_score" -v best="$best_score" '
        BEGIN {
            d = current - best
            if (best != 0) {
                dp = (d / (best < 0 ? -best : best)) * 100
            } else {
                dp = (d != 0) ? 100 : 0
            }

            v = (current > best) ? "keep" : "discard"

            printf "%s %.6f %.4f\n", v, d, dp
        }'
    )

    # 5. If keep → update state
    if [[ "$verdict" == "keep" ]]; then
        state_set "best_score" "$current_score" --number
        local commit_hash
        commit_hash=$(git rev-parse --short HEAD 2>/dev/null || echo "none")
        state_set "best_commit" "$commit_hash"
        log_ok "KEEP: $current_score (was $best_score, delta: $delta)"
    else
        log_warn "DISCARD: $current_score (best: $best_score, delta: $delta)"
    fi

    # 6. JSON output
    echo "{\"verdict\":\"${verdict}\",\"current_score\":${current_score},\"best_score\":${best_score},\"delta\":${delta},\"delta_pct\":${delta_pct}}"

    # 7. Exit code
    if [[ "$verdict" == "keep" ]]; then
        exit 0
    else
        exit 1
    fi
}

# Only run main if not being sourced (for testing)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
