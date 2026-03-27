#!/usr/bin/env bash
# AutoCode Project Setup — detects project type and generates .autocode.yaml
# Usage: bash setup.sh [--config .autocode.yaml] [--dry-run] [--force]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# ─── Project Type Detection ───
detect_project_type() {
    local dir="${1:-.}"

    # 1. package.json with frontend keywords
    if [[ -f "$dir/package.json" ]]; then
        local pkg_content
        pkg_content=$(cat "$dir/package.json")
        if echo "$pkg_content" | grep -qE '"(vite|webpack|next|react)"'; then
            echo "web-frontend"
            return 0
        fi
        # 2. package.json with backend keywords
        if echo "$pkg_content" | grep -qE '"(express|fastify|koa|nest)"'; then
            echo "web-backend"
            return 0
        fi
    fi

    # 3. Rust
    if [[ -f "$dir/Cargo.toml" ]]; then
        echo "rust"
        return 0
    fi

    # 4. Go
    if [[ -f "$dir/go.mod" ]]; then
        echo "go"
        return 0
    fi

    # 5. Java
    if [[ -f "$dir/pom.xml" ]] || [[ -f "$dir/build.gradle" ]] || [[ -f "$dir/build.gradle.kts" ]]; then
        echo "java"
        return 0
    fi

    # 6. Docker (standalone)
    if [[ -f "$dir/Dockerfile" ]]; then
        echo "docker"
        return 0
    fi

    # 7. Python
    if [[ -f "$dir/requirements.txt" ]] || [[ -f "$dir/setup.py" ]] || [[ -f "$dir/pyproject.toml" ]]; then
        echo "python"
        return 0
    fi

    # 8. Custom
    echo "custom"
}

# ─── YAML Generation ───
generate_yaml() {
    local project_type="$1"
    local config_file="$2"
    local dry_run="${3:-false}"

    local yaml_content=""

    case "$project_type" in
        web-frontend)
            yaml_content=$(cat <<'YAML_EOF'
# AutoCode Configuration — web-frontend
target_files:
  - "src/**/*.{ts,tsx,js,jsx}"

gates:
  - name: build
    command: "npm run build"
    expect: exit_code_0
    optional: false
  - name: test
    command: "npm test"
    expect: exit_code_0
    optional: false

objectives:
  - name: bundle_size_kb
    command: "npm run build 2>&1 | tail -5"
    parse: "([0-9.]+)\\s*kB"
    weight: 1.0
    direction: lower

readonly:
  - "*.test.*"
  - "*.spec.*"
  - "package.json"
  - "tsconfig.json"

changeset:
  max_files: 1
  max_lines: 100
YAML_EOF
)
            ;;
        web-backend)
            yaml_content=$(cat <<'YAML_EOF'
# AutoCode Configuration — web-backend
target_files:
  - "src/**/*.{ts,js}"

gates:
  - name: build
    command: "npm run build"
    expect: exit_code_0
    optional: false
  - name: test
    command: "npm test"
    expect: exit_code_0
    optional: false

objectives:
  - name: response_time_ms
    command: "npm test 2>&1 | tail -10"
    parse: "([0-9.]+)\\s*ms"
    weight: 1.0
    direction: lower

readonly:
  - "*.test.*"
  - "*.spec.*"
  - "package.json"
  - "tsconfig.json"

changeset:
  max_files: 1
  max_lines: 100
YAML_EOF
)
            ;;
        rust)
            yaml_content=$(cat <<'YAML_EOF'
# AutoCode Configuration — rust
target_files:
  - "src/**/*.rs"

gates:
  - name: build
    command: "cargo build"
    expect: exit_code_0
    optional: false
  - name: test
    command: "cargo test"
    expect: exit_code_0
    optional: false

objectives:
  - name: execution_time_ms
    command: "cargo test -- --bench 2>&1 | tail -5"
    parse: "([0-9.]+)\\s*ms"
    weight: 1.0
    direction: lower

readonly:
  - "tests/**"
  - "Cargo.toml"
  - "Cargo.lock"

changeset:
  max_files: 1
  max_lines: 100
YAML_EOF
)
            ;;
        go)
            yaml_content=$(cat <<'YAML_EOF'
# AutoCode Configuration — go
target_files:
  - "**/*.go"

gates:
  - name: build
    command: "go build ./..."
    expect: exit_code_0
    optional: false
  - name: test
    command: "go test ./..."
    expect: exit_code_0
    optional: false

objectives:
  - name: execution_time_ms
    command: "go test -bench=. ./... 2>&1 | tail -10"
    parse: "([0-9.]+)\\s*ns/op"
    weight: 1.0
    direction: lower

readonly:
  - "*_test.go"
  - "go.mod"
  - "go.sum"

changeset:
  max_files: 1
  max_lines: 100
YAML_EOF
)
            ;;
        java)
            yaml_content=$(cat <<'YAML_EOF'
# AutoCode Configuration — java
target_files:
  - "src/main/**/*.java"

gates:
  - name: build
    command: "./gradlew build"
    expect: exit_code_0
    optional: false

objectives:
  - name: build_time_s
    command: "./gradlew build 2>&1 | tail -5"
    parse: "([0-9.]+)\\s*s"
    weight: 1.0
    direction: lower

readonly:
  - "src/test/**"
  - "build.gradle"
  - "build.gradle.kts"
  - "pom.xml"

changeset:
  max_files: 1
  max_lines: 100
YAML_EOF
)
            ;;
        docker)
            yaml_content=$(cat <<'YAML_EOF'
# AutoCode Configuration — docker
target_files:
  - "Dockerfile"
  - "src/**/*"

gates:
  - name: build
    command: "docker build -t autocode-test ."
    expect: exit_code_0
    optional: false

objectives:
  - name: image_size_mb
    command: "docker image inspect autocode-test --format='{{.Size}}' | awk '{printf \"%.2f\", $1/1048576}'"
    parse: "([0-9.]+)"
    weight: 1.0
    direction: lower

readonly:
  - "docker-compose*.yml"

changeset:
  max_files: 1
  max_lines: 100
YAML_EOF
)
            ;;
        python)
            yaml_content=$(cat <<'YAML_EOF'
# AutoCode Configuration — python
target_files:
  - "**/*.py"

gates:
  - name: test
    command: "python -m pytest"
    expect: exit_code_0
    optional: false

objectives:
  - name: execution_time_ms
    command: "python -m pytest --tb=no -q 2>&1 | tail -3"
    parse: "([0-9.]+)s"
    weight: 1.0
    direction: lower

readonly:
  - "tests/**"
  - "test_*.py"
  - "requirements.txt"
  - "pyproject.toml"

changeset:
  max_files: 1
  max_lines: 100
YAML_EOF
)
            ;;
        custom)
            yaml_content=$(cat <<'YAML_EOF'
# AutoCode Configuration — custom
# TODO: Configure target_files, gates, and objectives for your project.

target_files:
  - "src/**/*"

gates:
  - name: build
    command: "echo 'No build command configured'"
    expect: exit_code_0
    optional: false

objectives:
  - name: metric
    command: "echo '0'"
    parse: "([0-9.]+)"
    weight: 1.0
    direction: lower

readonly: []

changeset:
  max_files: 1
  max_lines: 100
YAML_EOF
)
            ;;
    esac

    if [[ "$dry_run" == "true" ]]; then
        log_info "[dry-run] Would write $config_file with project type: $project_type"
        echo "$yaml_content"
        return 0
    fi

    echo "$yaml_content" > "$config_file"
    log_ok "Generated $config_file (type: $project_type)"
}

# ─── Environment Validation ───
validate_environment() {
    local project_type="$1"
    local warnings=0

    # git is required
    if ! command -v git >/dev/null 2>&1; then
        log_fail "git is required but not found"
        return 1
    fi
    log_ok "git found"

    # Ensure git repo exists
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        log_warn "Not a git repository. Initializing..."
        git init -q
        git add -A
        git commit -q -m "Initial commit (auto-created by autocode)" --allow-empty
        log_ok "Git repository initialized"
    fi

    # Project-specific tool checks
    case "$project_type" in
        web-frontend|web-backend)
            if command -v npm >/dev/null 2>&1; then
                log_ok "npm found"
            else
                log_warn "npm not found (required for $project_type)"
                warnings=$((warnings + 1))
            fi
            ;;
        rust)
            if command -v cargo >/dev/null 2>&1; then
                log_ok "cargo found"
            else
                log_warn "cargo not found (required for $project_type)"
                warnings=$((warnings + 1))
            fi
            ;;
        go)
            if command -v go >/dev/null 2>&1; then
                log_ok "go found"
            else
                log_warn "go not found (required for $project_type)"
                warnings=$((warnings + 1))
            fi
            ;;
        java)
            if [[ -x "./gradlew" ]] || command -v gradle >/dev/null 2>&1; then
                log_ok "gradle found"
            elif command -v mvn >/dev/null 2>&1; then
                log_ok "maven found"
            else
                log_warn "gradle/maven not found (required for $project_type)"
                warnings=$((warnings + 1))
            fi
            ;;
        docker)
            if command -v docker >/dev/null 2>&1; then
                log_ok "docker found"
            else
                log_warn "docker not found (required for $project_type)"
                warnings=$((warnings + 1))
            fi
            ;;
        python)
            if command -v python >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1; then
                log_ok "python found"
            else
                log_warn "python not found (required for $project_type)"
                warnings=$((warnings + 1))
            fi
            ;;
    esac

    # jq is recommended
    if command -v jq >/dev/null 2>&1; then
        log_ok "jq found"
    else
        log_warn "jq not found (recommended for JSON processing)"
    fi

    return 0
}

# ─── Main ───
main() {
    local dry_run=false
    local force=false
    local config="$CONFIG_FILE"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) dry_run=true; shift ;;
            --force)   force=true; shift ;;
            --config)  config="$2"; shift 2 ;;
            --help|-h)
                echo "AutoCode Setup Script"
                echo ""
                echo "Usage: bash setup.sh [--config .autocode.yaml] [--dry-run] [--force]"
                echo ""
                echo "Options:"
                echo "  --config FILE  Output config file path (default: .autocode.yaml)"
                echo "  --dry-run      Show what would be generated without writing"
                echo "  --force        Overwrite existing config file"
                echo "  --help         Show this help"
                return 0
                ;;
            *) log_warn "Unknown option: $1"; shift ;;
        esac
    done

    log_info "AutoCode Project Setup"
    echo ""

    # 1. Detect project type
    local project_type
    project_type=$(detect_project_type ".")
    log_info "Detected project type: $project_type"

    # 2. Check if config already exists
    if [[ -f "$config" ]] && [[ "$force" != "true" ]] && [[ "$dry_run" != "true" ]]; then
        log_warn "$config already exists. Use --force to overwrite."
        return 0
    fi

    # 3. Generate YAML
    generate_yaml "$project_type" "$config" "$dry_run"

    # 4. Validate environment
    echo ""
    log_info "Validating environment..."
    validate_environment "$project_type"

    # 5. Initialize (unless dry-run)
    if [[ "$dry_run" != "true" ]]; then
        echo ""
        bash "$SCRIPT_DIR/gate.sh" init --config "$config"
    fi

    # 6. Summary
    echo ""
    echo "==========================================="
    echo " AutoCode Setup Complete"
    echo "==========================================="
    echo " Project type: $project_type"
    echo " Config file:  $config"
    if [[ "$dry_run" == "true" ]]; then
        echo " Mode:         dry-run (no files written)"
    fi
    echo "==========================================="
}

# Only run main if not being sourced (for testing)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
