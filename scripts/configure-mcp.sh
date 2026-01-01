#!/usr/bin/env bash
# =============================================================================
# Configure MCP in Claude Code
# =============================================================================
# This script sets up the MCP configuration for Claude Code to connect
# to the Vikunja MCP server.
#
# Usage:
#   ./configure-mcp.sh [--local | --remote DOMAIN]
#
# Options:
#   --local           Configure for local Docker MCP server (default)
#   --remote DOMAIN   Configure for remote MCP server via Cloudflare tunnel
#   --test            Test the MCP connection after configuration
#
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Claude Code configuration paths
CLAUDE_CONFIG_DIR="${HOME}/.claude"
MCP_CONFIG_FILE="${CLAUDE_CONFIG_DIR}/mcp.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Defaults
MCP_PORT="${MCP_PORT:-3100}"
MODE="local"
REMOTE_DOMAIN=""
DO_TEST=false

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

check_claude_code() {
    log_info "Checking Claude Code installation..."

    if command -v claude &> /dev/null; then
        log_success "Claude Code CLI found"
        return 0
    fi

    log_warn "Claude Code CLI not found in PATH"
    echo ""
    echo "Install Claude Code:"
    echo "  npm install -g @anthropic-ai/claude-code"
    echo ""
    echo "Or visit: https://docs.anthropic.com/en/docs/claude-code"
    echo ""

    return 1
}

ensure_config_dir() {
    if [[ ! -d "$CLAUDE_CONFIG_DIR" ]]; then
        log_info "Creating Claude config directory..."
        mkdir -p "$CLAUDE_CONFIG_DIR"
    fi
}

get_vikunja_token() {
    # Try to get from .env file
    if [[ -f "$PROJECT_ROOT/.env" ]]; then
        local token
        token=$(grep -E "^VIKUNJA_API_TOKEN=" "$PROJECT_ROOT/.env" | cut -d= -f2- | tr -d '"' || true)
        if [[ -n "$token" ]]; then
            echo "$token"
            return 0
        fi
    fi

    return 1
}

get_mcp_auth_token() {
    # Try to get from .env file
    if [[ -f "$PROJECT_ROOT/.env" ]]; then
        local token
        token=$(grep -E "^MCP_AUTH_TOKEN=" "$PROJECT_ROOT/.env" | cut -d= -f2- | tr -d '"' || true)
        if [[ -n "$token" ]]; then
            echo "$token"
            return 0
        fi
    fi

    return 1
}

generate_local_config() {
    log_info "Generating local MCP configuration..."

    local vikunja_token=""
    local mcp_auth=""

    # Try to get tokens
    vikunja_token=$(get_vikunja_token || echo "")
    mcp_auth=$(get_mcp_auth_token || echo "")

    # Build the configuration
    cat > "$MCP_CONFIG_FILE" << EOF
{
  "mcpServers": {
    "vikunja": {
      "command": "docker",
      "args": [
        "exec",
        "-i",
        "vikunja-mcp",
        "node",
        "src/index.js"
      ],
      "env": {
        "VIKUNJA_API_URL": "http://vikunja:3456/api/v1",
        "VIKUNJA_API_TOKEN": "${vikunja_token}",
        "LOG_LEVEL": "info"
      }
    }
  }
}
EOF

    log_success "Local MCP configuration created at: $MCP_CONFIG_FILE"
}

generate_remote_config() {
    local domain="$1"
    log_info "Generating remote MCP configuration for: $domain"

    local mcp_auth=""
    mcp_auth=$(get_mcp_auth_token || echo "")

    # For remote, we use HTTP transport
    cat > "$MCP_CONFIG_FILE" << EOF
{
  "mcpServers": {
    "vikunja": {
      "url": "https://${domain}/mcp",
      "transport": "http",
      "headers": {
        "Authorization": "Bearer ${mcp_auth}"
      }
    }
  }
}
EOF

    log_success "Remote MCP configuration created at: $MCP_CONFIG_FILE"
}

generate_stdio_config() {
    log_info "Generating stdio MCP configuration (runs MCP server directly)..."

    local vikunja_token=""
    vikunja_token=$(get_vikunja_token || echo "")

    # Get the MCP server path
    local mcp_server_path="${PROJECT_ROOT}/mcp-server"

    cat > "$MCP_CONFIG_FILE" << EOF
{
  "mcpServers": {
    "vikunja": {
      "command": "node",
      "args": ["${mcp_server_path}/src/index.js"],
      "env": {
        "VIKUNJA_API_URL": "http://localhost:3456/api/v1",
        "VIKUNJA_API_TOKEN": "${vikunja_token}",
        "LOG_LEVEL": "info"
      }
    }
  }
}
EOF

    log_success "Stdio MCP configuration created at: $MCP_CONFIG_FILE"
}

backup_existing_config() {
    if [[ -f "$MCP_CONFIG_FILE" ]]; then
        local backup_file="${MCP_CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "Backing up existing config to: $backup_file"
        cp "$MCP_CONFIG_FILE" "$backup_file"
    fi
}

test_mcp_connection() {
    log_info "Testing MCP connection..."

    if [[ "$MODE" == "local" ]]; then
        # Test local Docker-based MCP
        if docker exec vikunja-mcp node -e "console.log('MCP server reachable')" 2>/dev/null; then
            log_success "MCP server container is running"
        else
            log_error "Cannot reach MCP server container"
            echo "Make sure containers are running: docker compose up -d"
            return 1
        fi

        # Test Vikunja API connection
        if docker exec vikunja-mcp curl -sf "http://vikunja:3456/api/v1/info" > /dev/null 2>&1; then
            log_success "Vikunja API is reachable from MCP container"
        else
            log_warn "Cannot reach Vikunja API from MCP container"
        fi
    else
        # Test remote MCP
        if curl -sf "https://${REMOTE_DOMAIN}/health" > /dev/null 2>&1; then
            log_success "Remote MCP server is reachable"
        else
            log_error "Cannot reach remote MCP server at: https://${REMOTE_DOMAIN}"
            return 1
        fi
    fi

    log_success "MCP connection test passed"
}

show_next_steps() {
    echo ""
    echo "=============================================="
    echo "  Configuration Complete!"
    echo "=============================================="
    echo ""
    echo "MCP configuration saved to: $MCP_CONFIG_FILE"
    echo ""

    if [[ -z "$(get_vikunja_token || echo '')" ]]; then
        echo "IMPORTANT: You need to set up a Vikunja API token:"
        echo ""
        echo "1. Open Vikunja at http://localhost:3456"
        echo "2. Go to Settings > API Tokens"
        echo "3. Create a new token with appropriate permissions"
        echo "4. Add to .env: VIKUNJA_API_TOKEN=your-token"
        echo "5. Run this script again to update the config"
        echo ""
    fi

    echo "To use with Claude Code:"
    echo "  claude              # Start Claude Code"
    echo "  /mcp                # List available MCP servers"
    echo ""
    echo "Available Vikunja tools:"
    echo "  - vikunja_list_projects"
    echo "  - vikunja_list_tasks"
    echo "  - vikunja_create_task"
    echo "  - vikunja_update_task"
    echo "  - vikunja_complete_task"
    echo "  - vikunja_delete_task"
    echo "  - vikunja_search_tasks"
    echo "  - vikunja_list_labels"
    echo ""
}

show_help() {
    cat << EOF
Configure MCP in Claude Code

Usage: $(basename "$0") [OPTIONS]

Options:
    --local               Configure for local Docker MCP server (default)
    --remote DOMAIN       Configure for remote MCP server via Cloudflare tunnel
    --stdio               Configure for direct stdio connection (no Docker)
    --test                Test the MCP connection after configuration
    -h, --help            Show this help message

Examples:
    # Configure for local Docker MCP
    ./$(basename "$0") --local

    # Configure for remote server
    ./$(basename "$0") --remote mcp.example.com

    # Configure and test
    ./$(basename "$0") --local --test

Environment Variables (read from .env):
    VIKUNJA_API_TOKEN    Vikunja API token
    MCP_AUTH_TOKEN       MCP server authentication token
    MCP_PORT             MCP server port (default: 3100)
EOF
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --local)
                MODE="local"
                shift
                ;;
            --remote)
                MODE="remote"
                REMOTE_DOMAIN="$2"
                shift 2
                ;;
            --stdio)
                MODE="stdio"
                shift
                ;;
            --test)
                DO_TEST=true
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

    echo "=============================================="
    echo "  Claude Code MCP Configuration"
    echo "=============================================="
    echo ""

    # Check for Claude Code (warn but continue)
    check_claude_code || true

    ensure_config_dir
    backup_existing_config

    case "$MODE" in
        local)
            generate_local_config
            ;;
        remote)
            if [[ -z "$REMOTE_DOMAIN" ]]; then
                log_error "--remote requires a domain"
                exit 1
            fi
            generate_remote_config "$REMOTE_DOMAIN"
            ;;
        stdio)
            generate_stdio_config
            ;;
    esac

    if [[ "$DO_TEST" == "true" ]]; then
        test_mcp_connection
    fi

    show_next_steps
}

main "$@"
