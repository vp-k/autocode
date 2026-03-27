#!/usr/bin/env bash
# AutoCode Installer for Claude Code
# Usage: bash install.sh [--prefix ~/.claude] [--uninstall] [--update]
set -euo pipefail

# ─── Defaults ────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${HOME}/.claude"
ACTION="install"

# ─── Parse Arguments ─────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix)
            PREFIX="$2"
            shift 2
            ;;
        --uninstall)
            ACTION="uninstall"
            shift
            ;;
        --update)
            ACTION="update"
            shift
            ;;
        --help|-h)
            echo "AutoCode Installer for Claude Code"
            echo ""
            echo "Usage: bash install.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --prefix DIR   Install prefix (default: ~/.claude)"
            echo "  --uninstall    Remove installed files (preserves user data)"
            echo "  --update       Remove and reinstall (preserves user data)"
            echo "  --help, -h     Show this help"
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1"
            echo "Run 'bash install.sh --help' for usage."
            exit 1
            ;;
    esac
done

# ─── Paths ───────────────────────────────────────────────────
CMD_DIR="${PREFIX}/commands"
SCRIPTS_DIR="${CMD_DIR}/autocode-scripts"
TEMPLATES_DIR="${CMD_DIR}/autocode-templates"
AUTOCODE_MD="${CMD_DIR}/autocode.md"

# ─── Colors ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }

# ─── Uninstall ───────────────────────────────────────────────
do_uninstall() {
    info "Uninstalling AutoCode from ${PREFIX}..."

    if [[ -f "${AUTOCODE_MD}" ]]; then
        rm -f "${AUTOCODE_MD}"
        ok "Removed ${AUTOCODE_MD}"
    fi

    if [[ -d "${SCRIPTS_DIR}" ]]; then
        rm -rf "${SCRIPTS_DIR}"
        ok "Removed ${SCRIPTS_DIR}"
    fi

    if [[ -d "${TEMPLATES_DIR}" ]]; then
        rm -rf "${TEMPLATES_DIR}"
        ok "Removed ${TEMPLATES_DIR}"
    fi

    ok "Uninstall complete. User data (.autocode/) in projects was preserved."
}

# ─── Install ─────────────────────────────────────────────────
do_install() {
    info "Installing AutoCode to ${PREFIX}..."

    # Validate source files exist
    [[ -f "${SCRIPT_DIR}/commands/autocode.md" ]] || fail "Source commands/autocode.md not found. Run from the autoresearch repo root."
    [[ -d "${SCRIPT_DIR}/scripts" ]]              || fail "Source scripts/ directory not found."
    [[ -d "${SCRIPT_DIR}/templates" ]]            || fail "Source templates/ directory not found."

    # Create directories
    mkdir -p "${CMD_DIR}"
    mkdir -p "${SCRIPTS_DIR}"
    mkdir -p "${TEMPLATES_DIR}"

    # Copy scripts (including lib/)
    cp -r "${SCRIPT_DIR}/scripts/"* "${SCRIPTS_DIR}/"
    ok "Copied scripts -> ${SCRIPTS_DIR}"

    # Copy templates
    cp -r "${SCRIPT_DIR}/templates/"* "${TEMPLATES_DIR}/"
    ok "Copied templates -> ${TEMPLATES_DIR}"

    # Copy autocode.md and rewrite script paths
    # Using | as sed delimiter; escape & and | in the replacement path
    ESCAPED_SCRIPTS_DIR=$(printf '%s' "${SCRIPTS_DIR}" | sed 's/[&|\\]/\\&/g')
    sed "s|scripts/|${ESCAPED_SCRIPTS_DIR}/|g" "${SCRIPT_DIR}/commands/autocode.md" > "${AUTOCODE_MD}"
    ok "Copied autocode.md -> ${AUTOCODE_MD} (paths rewritten)"

    # chmod +x all shell scripts
    find "${SCRIPTS_DIR}" -name "*.sh" -exec chmod +x {} \;
    ok "Made scripts executable"

    # ─── Verify Installation ─────────────────────────────────
    info "Verifying installation..."

    if bash "${SCRIPTS_DIR}/gate.sh" help >/dev/null 2>&1; then
        ok "gate.sh help -> OK"
    else
        warn "gate.sh help returned non-zero (may require project context)"
    fi

    echo ""
    ok "Installation complete!"
    echo ""
    info "Installed files:"
    echo "  Command:   ${AUTOCODE_MD}"
    echo "  Scripts:   ${SCRIPTS_DIR}/"
    echo "  Templates: ${TEMPLATES_DIR}/"
    echo ""
    info "Usage: In any project, create .autocode.yaml and run /autocode"
    info "Templates available in: ${TEMPLATES_DIR}/"
}

# ─── Main ────────────────────────────────────────────────────
case "${ACTION}" in
    install)
        if [[ -f "${AUTOCODE_MD}" ]]; then
            warn "AutoCode is already installed at ${PREFIX}."
            warn "Use --update to reinstall or --uninstall to remove."
            exit 1
        fi
        do_install
        ;;
    uninstall)
        do_uninstall
        ;;
    update)
        info "Updating AutoCode..."
        do_uninstall
        echo ""
        do_install
        ;;
esac
