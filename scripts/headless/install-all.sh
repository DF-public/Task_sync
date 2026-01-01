#!/usr/bin/env bash
# =============================================================================
# Master Installation Script for Claude Code Headless Operation
# =============================================================================
# Purpose: Complete installation of all components for headless Claude Code
#          operation with Todoist/Vikunja synchronization.
#
# Usage:
#   sudo ./install-all.sh
#
# What gets installed:
#   - Logging configuration
#   - MCP server and skills
#   - Cron jobs for import/export
#   - State directories
#
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALL_LOG="/var/log/claude-code/install-$(date +%Y%m%d-%H%M%S).log"
CLAUDE_USER="${CLAUDE_USER:-$USER}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

log() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] $*"
    echo -e "${BLUE}[INFO]${NC} $*"

    # Create log directory if needed
    mkdir -p "$(dirname "$INSTALL_LOG")" 2>/dev/null || true
    echo "$message" >> "$INSTALL_LOG" 2>/dev/null || true
}

log_ok() {
    echo -e "${GREEN}[OK]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        log_warn "Not running as root - some features may be limited"
        log "For full installation, run: sudo $0"
        echo ""
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# -----------------------------------------------------------------------------
# Installation Steps
# -----------------------------------------------------------------------------

install_dependencies() {
    log "Step 1: Checking dependencies..."

    local missing=()

    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi

    if ! command -v curl &> /dev/null; then
        missing+=("curl")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_warn "Missing dependencies: ${missing[*]}"

        if [[ "$EUID" -eq 0 ]]; then
            log "Installing missing dependencies..."
            if command -v apt-get &> /dev/null; then
                apt-get update -qq
                apt-get install -y -qq "${missing[@]}"
            elif command -v apk &> /dev/null; then
                apk add --no-cache "${missing[@]}"
            elif command -v yum &> /dev/null; then
                yum install -y -q "${missing[@]}"
            else
                log_error "Cannot install dependencies automatically"
                log "Please install: ${missing[*]}"
                exit 1
            fi
        else
            log_error "Cannot install dependencies without root"
            log "Please install: ${missing[*]}"
            exit 1
        fi
    fi

    log_ok "Dependencies satisfied"
}

setup_logging() {
    log "Step 2: Configuring logging..."

    bash "$SCRIPT_DIR/setup-logging.sh" || {
        log_warn "Logging setup had issues, continuing..."
    }

    log_ok "Logging configured"
}

setup_mcp_skills() {
    log "Step 3: Setting up MCP server and skills..."

    if [[ "$EUID" -eq 0 ]]; then
        sudo -u "$CLAUDE_USER" bash "$SCRIPT_DIR/setup-mcp-skills.sh"
    else
        bash "$SCRIPT_DIR/setup-mcp-skills.sh"
    fi

    log_ok "MCP and skills configured"
}

make_scripts_executable() {
    log "Step 4: Setting script permissions..."

    chmod +x "$SCRIPT_DIR"/*.sh
    chmod +x "$PROJECT_ROOT/scripts"/*.sh 2>/dev/null || true

    if [[ "$EUID" -eq 0 ]]; then
        chown -R "$CLAUDE_USER:$CLAUDE_USER" "$SCRIPT_DIR"
    fi

    log_ok "Script permissions set"
}

install_cron_jobs() {
    log "Step 5: Installing cron jobs..."

    if [[ "$EUID" -eq 0 ]] && [[ -d "/etc/cron.d" ]]; then
        # Import cron job - every hour
        cat > /etc/cron.d/claude-import <<EOF
# Claude Code: Import tasks every hour
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/bin:/bin
LOG_DIR=/var/log/claude-code
STATE_DIR=/home/$CLAUDE_USER/sync-state

0 * * * * $CLAUDE_USER $SCRIPT_DIR/import-tasks.sh >> /var/log/claude-code/cron.log 2>&1
EOF

        # Export cron job - every 2 hours during daytime (8am-8pm)
        cat > /etc/cron.d/claude-export <<EOF
# Claude Code: Export status every 2 hours during daytime
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/bin:/bin
LOG_DIR=/var/log/claude-code
STATE_DIR=/home/$CLAUDE_USER/sync-state

0 8-20/2 * * * $CLAUDE_USER $SCRIPT_DIR/export-status.sh >> /var/log/claude-code/cron.log 2>&1
EOF

        chmod 644 /etc/cron.d/claude-import /etc/cron.d/claude-export

        log_ok "Cron jobs installed to /etc/cron.d/"
    else
        log_warn "Skipping system cron installation (requires root)"
        log "Install user crontab manually with: crontab -e"
        echo ""
        echo "Add these lines:"
        echo "  # Import tasks every hour"
        echo "  0 * * * * $SCRIPT_DIR/import-tasks.sh >> /var/log/claude-code/cron.log 2>&1"
        echo ""
        echo "  # Export status every 2 hours (8am-8pm)"
        echo "  0 8-20/2 * * * $SCRIPT_DIR/export-status.sh >> /var/log/claude-code/cron.log 2>&1"
        echo ""
    fi
}

validate_installation() {
    log "Step 6: Validating installation..."

    local errors=0

    # Check required files
    local required_files=(
        "$SCRIPT_DIR/import-tasks.sh"
        "$SCRIPT_DIR/export-status.sh"
        "$SCRIPT_DIR/setup-mcp-skills.sh"
        "$PROJECT_ROOT/skills/task-import.md"
        "$PROJECT_ROOT/skills/task-export.md"
    )

    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_error "Missing required file: $file"
            ((errors++))
        fi
    done

    # Check state directory
    local state_dir="${HOME}/sync-state"
    if [[ ! -d "$state_dir" ]]; then
        log_warn "State directory not found: $state_dir"
    fi

    # Check MCP config
    local mcp_config="${HOME}/.config/claude-code/mcp.json"
    if [[ -f "$mcp_config" ]]; then
        if jq empty "$mcp_config" 2>/dev/null; then
            log_ok "MCP configuration valid"
        else
            log_error "MCP configuration is invalid JSON"
            ((errors++))
        fi
    else
        log_warn "MCP configuration not found: $mcp_config"
    fi

    if [[ $errors -gt 0 ]]; then
        log_error "Validation failed with $errors errors"
        return 1
    fi

    log_ok "All validations passed"
}

print_summary() {
    echo ""
    echo "=============================================="
    echo -e "${GREEN}  Installation Completed Successfully${NC}"
    echo "=============================================="
    echo ""
    echo "Installed Components:"
    echo "  - MCP Server Configuration"
    echo "  - Skills: task-import.md, task-export.md"
    echo "  - Import Script (hourly cron)"
    echo "  - Export Script (every 2h, 8am-8pm)"
    echo "  - Logging with rotation"
    echo ""
    echo "Locations:"
    echo "  - Scripts: $SCRIPT_DIR/"
    echo "  - Skills: $PROJECT_ROOT/skills/"
    echo "  - State: ${HOME}/sync-state/"
    echo "  - Logs: /var/log/claude-code/"
    echo "  - MCP Config: ${HOME}/.config/claude-code/mcp.json"
    echo ""
    echo "Manual Steps Required:"
    echo "  1. Set environment variables:"
    echo "     export VIKUNJA_API_TOKEN='your-token'"
    echo "     export TODOIST_API_TOKEN='your-token'"
    echo ""
    echo "  2. Start Docker containers:"
    echo "     cd $PROJECT_ROOT && docker compose up -d"
    echo ""
    echo "  3. Test import:"
    echo "     $SCRIPT_DIR/import-tasks.sh --verbose"
    echo ""
    echo "  4. Verify cron jobs:"
    if [[ -f "/etc/cron.d/claude-import" ]]; then
        echo "     cat /etc/cron.d/claude-import"
    else
        echo "     crontab -l"
    fi
    echo ""
    echo "Logs:"
    echo "  tail -f /var/log/claude-code/import-\$(date +%Y%m%d).log"
    echo ""
    if [[ -f "$INSTALL_LOG" ]]; then
        echo "Install log: $INSTALL_LOG"
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
    echo "=============================================="
    echo "  Claude Code Headless Installation"
    echo "=============================================="
    echo ""

    check_root

    log "========== Starting Installation =========="

    install_dependencies
    setup_logging
    setup_mcp_skills
    make_scripts_executable
    install_cron_jobs
    validate_installation

    log "========== Installation Complete =========="

    print_summary
}

main "$@"
