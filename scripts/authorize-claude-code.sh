#!/usr/bin/env bash
# =============================================================================
# Claude Code Authorization Script
# =============================================================================
# This script handles Claude Code subscription authentication and validation.
#
# Usage:
#   ./authorize-claude-code.sh [--check | --login | --status]
#
# Options:
#   --check     Check if Claude Code is authorized (default)
#   --login     Launch interactive login
#   --status    Show detailed subscription status
#   --refresh   Refresh authentication token
#
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Claude Code paths
CLAUDE_CONFIG_DIR="${HOME}/.claude"
CLAUDE_CREDENTIALS="${CLAUDE_CONFIG_DIR}/credentials.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_claude_installed() {
    if ! command -v claude &> /dev/null; then
        log_error "Claude Code is not installed"
        echo ""
        echo "Install Claude Code:"
        echo "  npm install -g @anthropic-ai/claude-code"
        echo ""
        echo "Or with npx:"
        echo "  npx @anthropic-ai/claude-code"
        echo ""
        exit 1
    fi
    log_success "Claude Code CLI found: $(which claude)"
}

check_authorization() {
    log_info "Checking Claude Code authorization..."

    # Check if credentials file exists
    if [[ ! -f "$CLAUDE_CREDENTIALS" ]]; then
        log_warn "No credentials file found"
        return 1
    fi

    # Try to validate by running a simple command
    if claude --version &> /dev/null; then
        log_success "Claude Code is installed and accessible"
    else
        log_error "Claude Code command failed"
        return 1
    fi

    # Check for API key in environment
    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        log_success "ANTHROPIC_API_KEY is set in environment"
        return 0
    fi

    # Check credentials file for token
    if [[ -f "$CLAUDE_CREDENTIALS" ]] && grep -q "api_key" "$CLAUDE_CREDENTIALS" 2>/dev/null; then
        log_success "API key found in credentials file"
        return 0
    fi

    log_warn "No API key configured"
    return 1
}

show_status() {
    echo "=============================================="
    echo "  Claude Code Authorization Status"
    echo "=============================================="
    echo ""

    # Version
    echo "Version Information:"
    if command -v claude &> /dev/null; then
        echo "  CLI Path: $(which claude)"
        echo "  Version: $(claude --version 2>/dev/null || echo 'unknown')"
    else
        echo "  Claude Code: NOT INSTALLED"
    fi
    echo ""

    # Configuration
    echo "Configuration:"
    echo "  Config Dir: $CLAUDE_CONFIG_DIR"
    echo "  Credentials: $([ -f "$CLAUDE_CREDENTIALS" ] && echo 'EXISTS' || echo 'NOT FOUND')"
    echo "  MCP Config: $([ -f "${CLAUDE_CONFIG_DIR}/mcp.json" ] && echo 'EXISTS' || echo 'NOT FOUND')"
    echo ""

    # API Key Status
    echo "Authentication:"
    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        # Mask the API key
        local masked_key="${ANTHROPIC_API_KEY:0:10}...${ANTHROPIC_API_KEY: -4}"
        echo "  ANTHROPIC_API_KEY: SET ($masked_key)"
    else
        echo "  ANTHROPIC_API_KEY: NOT SET"
    fi

    if [[ -f "$CLAUDE_CREDENTIALS" ]]; then
        if grep -q "api_key" "$CLAUDE_CREDENTIALS" 2>/dev/null; then
            echo "  Credentials File: CONTAINS API KEY"
        else
            echo "  Credentials File: EXISTS (no API key)"
        fi
    fi
    echo ""

    # MCP Servers
    if [[ -f "${CLAUDE_CONFIG_DIR}/mcp.json" ]]; then
        echo "MCP Servers Configured:"
        if command -v jq &> /dev/null; then
            jq -r '.mcpServers | keys[]' "${CLAUDE_CONFIG_DIR}/mcp.json" 2>/dev/null | while read -r server; do
                echo "  - $server"
            done
        else
            echo "  (install jq for detailed view)"
        fi
    fi
    echo ""
}

do_login() {
    log_info "Starting Claude Code login..."
    echo ""

    # Check if already authorized
    if check_authorization 2>/dev/null; then
        log_success "Already authorized!"
        echo ""
        read -p "Re-authenticate anyway? [y/N] " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi

    echo "=============================================="
    echo "  Claude Code Authorization"
    echo "=============================================="
    echo ""
    echo "You have two options to authorize Claude Code:"
    echo ""
    echo "Option 1: API Key (Recommended for automation)"
    echo "  1. Go to: https://console.anthropic.com/settings/keys"
    echo "  2. Create a new API key"
    echo "  3. Set environment variable:"
    echo "     export ANTHROPIC_API_KEY='your-api-key'"
    echo ""
    echo "Option 2: Interactive Login"
    echo "  Run: claude login"
    echo "  This will open a browser for authentication"
    echo ""

    read -p "Would you like to set an API key now? [y/N] " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        read -sp "Enter your Anthropic API key: " api_key
        echo ""

        if [[ -z "$api_key" ]]; then
            log_error "No API key provided"
            exit 1
        fi

        # Validate key format (basic check)
        if [[ ! "$api_key" =~ ^sk-ant- ]]; then
            log_warn "API key doesn't match expected format (sk-ant-...)"
            read -p "Continue anyway? [y/N] " -n 1 -r
            echo ""
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi

        # Save to .env file
        if [[ -f "$PROJECT_ROOT/.env" ]]; then
            # Check if already exists
            if grep -q "^ANTHROPIC_API_KEY=" "$PROJECT_ROOT/.env"; then
                sed -i "s|^ANTHROPIC_API_KEY=.*|ANTHROPIC_API_KEY=${api_key}|" "$PROJECT_ROOT/.env"
            else
                echo "" >> "$PROJECT_ROOT/.env"
                echo "# Claude Code API Key" >> "$PROJECT_ROOT/.env"
                echo "ANTHROPIC_API_KEY=${api_key}" >> "$PROJECT_ROOT/.env"
            fi
            log_success "API key saved to .env"
        fi

        # Also add to shell profile for convenience
        echo ""
        echo "To use immediately, run:"
        echo "  export ANTHROPIC_API_KEY='${api_key:0:10}...'"
        echo ""
        echo "To persist, add to your shell profile (~/.bashrc or ~/.zshrc):"
        echo "  echo 'export ANTHROPIC_API_KEY=\"your-key\"' >> ~/.bashrc"
        echo ""
    else
        echo ""
        log_info "Running interactive login..."
        echo ""
        claude login
    fi

    echo ""
    log_success "Authorization complete!"
}

refresh_auth() {
    log_info "Refreshing Claude Code authentication..."

    # If using API key, just validate it
    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        log_info "API key is set in environment"
        # Test the key by making a simple request
        if claude --version &> /dev/null; then
            log_success "Authentication valid"
        else
            log_error "Authentication failed - check your API key"
            exit 1
        fi
    else
        # Try interactive refresh
        log_info "No API key set, attempting interactive refresh..."
        claude login
    fi
}

show_help() {
    cat << EOF
Claude Code Authorization Script

Usage: $(basename "$0") [OPTIONS]

Options:
    --check      Check if Claude Code is authorized (default)
    --login      Launch interactive login / set API key
    --status     Show detailed authorization status
    --refresh    Refresh authentication token
    -h, --help   Show this help message

Environment Variables:
    ANTHROPIC_API_KEY    Anthropic API key for Claude

Examples:
    # Check authorization status
    ./$(basename "$0") --check

    # Set up authorization
    ./$(basename "$0") --login

    # Show detailed status
    ./$(basename "$0") --status

Getting an API Key:
    1. Visit: https://console.anthropic.com/settings/keys
    2. Create a new API key
    3. Set as environment variable or save to .env

EOF
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
    local action="check"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --check)
                action="check"
                shift
                ;;
            --login)
                action="login"
                shift
                ;;
            --status)
                action="status"
                shift
                ;;
            --refresh)
                action="refresh"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    check_claude_installed

    case "$action" in
        check)
            if check_authorization; then
                log_success "Claude Code is authorized and ready!"
                exit 0
            else
                log_error "Claude Code is not authorized"
                echo "Run: $(basename "$0") --login"
                exit 1
            fi
            ;;
        login)
            do_login
            ;;
        status)
            show_status
            ;;
        refresh)
            refresh_auth
            ;;
    esac
}

main "$@"
