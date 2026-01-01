#!/usr/bin/env bash
# =============================================================================
# Deploy Vikunja MCP through Cloudflare Tunnel
# =============================================================================
# This script configures and deploys the Vikunja MCP server through an
# existing Cloudflare Zero Trust tunnel.
#
# Prerequisites:
#   - Cloudflare account with Zero Trust access
#   - Existing tunnel configured in Cloudflare dashboard
#   - cloudflared installed (for local configuration testing)
#
# Usage:
#   ./deploy-vikunja-mcp.sh [--tunnel-name NAME] [--domain DOMAIN]
#
# Environment Variables:
#   CLOUDFLARE_TUNNEL_TOKEN  - Tunnel token from Cloudflare dashboard
#   CLOUDFLARE_TUNNEL_NAME   - Name of the tunnel (default: unified-task-sync)
#   MCP_DOMAIN               - Domain for MCP endpoint (e.g., mcp.example.com)
#
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Defaults
TUNNEL_NAME="${CLOUDFLARE_TUNNEL_NAME:-unified-task-sync}"
MCP_PORT="${MCP_PORT:-3100}"

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

check_requirements() {
    log_info "Checking requirements..."

    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        exit 1
    fi

    # Check Docker Compose
    if ! docker compose version &> /dev/null; then
        log_error "Docker Compose is not available"
        exit 1
    fi

    # Check for .env file
    if [[ ! -f "$PROJECT_ROOT/.env" ]]; then
        log_warn ".env file not found. Creating from template..."
        if [[ -f "$PROJECT_ROOT/.env.example" ]]; then
            cp "$PROJECT_ROOT/.env.example" "$PROJECT_ROOT/.env"
            log_warn "Please edit .env with your configuration"
        else
            log_error ".env.example not found"
            exit 1
        fi
    fi

    log_success "Requirements satisfied"
}

validate_tunnel_token() {
    log_info "Validating Cloudflare tunnel configuration..."

    # Source .env file
    set -a
    source "$PROJECT_ROOT/.env"
    set +a

    if [[ -z "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]]; then
        log_error "CLOUDFLARE_TUNNEL_TOKEN not set in .env"
        echo ""
        echo "To get your tunnel token:"
        echo "1. Go to Cloudflare Zero Trust Dashboard"
        echo "2. Navigate to Access > Tunnels"
        echo "3. Create or select a tunnel"
        echo "4. Copy the token from the 'Install connector' step"
        echo ""
        exit 1
    fi

    log_success "Tunnel token configured"
}

configure_tunnel_routes() {
    log_info "Configuring tunnel routes..."

    # Source .env file
    set -a
    source "$PROJECT_ROOT/.env"
    set +a

    local mcp_domain="${MCP_DOMAIN:-}"

    if [[ -z "$mcp_domain" ]]; then
        log_warn "MCP_DOMAIN not set - tunnel will be configured but no public hostname"
        echo ""
        echo "To expose MCP publicly, set MCP_DOMAIN in .env"
        echo "Example: MCP_DOMAIN=mcp.yourdomain.com"
        echo ""
        echo "Then configure in Cloudflare dashboard:"
        echo "1. Go to Zero Trust > Access > Tunnels"
        echo "2. Select your tunnel and click 'Configure'"
        echo "3. Add a public hostname:"
        echo "   - Subdomain: mcp (or your preferred subdomain)"
        echo "   - Domain: yourdomain.com"
        echo "   - Service: http://vikunja-mcp:${MCP_PORT}"
        echo ""
    else
        log_info "MCP will be available at: https://${mcp_domain}"
        echo ""
        echo "Ensure your Cloudflare tunnel is configured with:"
        echo "  - Hostname: ${mcp_domain}"
        echo "  - Service: http://vikunja-mcp:${MCP_PORT}"
        echo ""
    fi
}

build_mcp_server() {
    log_info "Building MCP server..."

    cd "$PROJECT_ROOT"
    docker compose build vikunja-mcp

    log_success "MCP server built successfully"
}

start_services() {
    log_info "Starting services..."

    cd "$PROJECT_ROOT"

    # Start core services first
    docker compose up -d vikunja db

    log_info "Waiting for Vikunja to be ready..."
    sleep 10

    # Start MCP server
    docker compose up -d vikunja-mcp

    log_info "Waiting for MCP server to be ready..."
    sleep 5

    # Start tunnel if token is configured
    set -a
    source "$PROJECT_ROOT/.env"
    set +a

    if [[ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]]; then
        log_info "Starting Cloudflare tunnel..."
        docker compose --profile tunnel up -d cloudflared
    fi

    log_success "Services started"
}

verify_deployment() {
    log_info "Verifying deployment..."

    # Check Vikunja
    if docker compose ps vikunja | grep -q "Up"; then
        log_success "Vikunja is running"
    else
        log_error "Vikunja is not running"
        docker compose logs vikunja --tail=20
    fi

    # Check MCP server
    if docker compose ps vikunja-mcp | grep -q "Up"; then
        log_success "MCP server is running"

        # Test health endpoint
        if curl -sf "http://localhost:${MCP_PORT}/health" > /dev/null 2>&1; then
            log_success "MCP server health check passed"
        else
            log_warn "MCP server health check failed (might need more time)"
        fi
    else
        log_error "MCP server is not running"
        docker compose logs vikunja-mcp --tail=20
    fi

    # Check tunnel (if enabled)
    if docker compose --profile tunnel ps cloudflared 2>/dev/null | grep -q "Up"; then
        log_success "Cloudflare tunnel is running"
    fi

    echo ""
    log_success "Deployment complete!"
    echo ""
    echo "Next steps:"
    echo "1. Configure Claude Code: ./scripts/configure-mcp.sh"
    echo "2. Generate Vikunja API token in Vikunja settings"
    echo "3. Update VIKUNJA_API_TOKEN in .env"
    echo ""
}

show_help() {
    cat << EOF
Deploy Vikunja MCP through Cloudflare Tunnel

Usage: $(basename "$0") [OPTIONS]

Options:
    --tunnel-name NAME    Cloudflare tunnel name (default: unified-task-sync)
    --domain DOMAIN       Domain for MCP endpoint
    --build-only          Only build, don't start services
    --no-tunnel           Don't start Cloudflare tunnel
    -h, --help            Show this help message

Environment Variables:
    CLOUDFLARE_TUNNEL_TOKEN   Tunnel token from Cloudflare dashboard
    CLOUDFLARE_TUNNEL_NAME    Name of the tunnel
    MCP_DOMAIN                Domain for MCP endpoint
    MCP_PORT                  Port for MCP server (default: 3100)

Examples:
    # Full deployment with tunnel
    export CLOUDFLARE_TUNNEL_TOKEN="your-token"
    ./$(basename "$0") --domain mcp.example.com

    # Build and start without tunnel
    ./$(basename "$0") --no-tunnel

    # Just build the MCP server
    ./$(basename "$0") --build-only
EOF
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
    local build_only=false
    local no_tunnel=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --tunnel-name)
                TUNNEL_NAME="$2"
                shift 2
                ;;
            --domain)
                export MCP_DOMAIN="$2"
                shift 2
                ;;
            --build-only)
                build_only=true
                shift
                ;;
            --no-tunnel)
                no_tunnel=true
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
    echo "  Vikunja MCP Deployment"
    echo "=============================================="
    echo ""

    check_requirements

    if [[ "$no_tunnel" == "false" ]]; then
        validate_tunnel_token
        configure_tunnel_routes
    fi

    build_mcp_server

    if [[ "$build_only" == "true" ]]; then
        log_success "Build complete (--build-only specified)"
        exit 0
    fi

    if [[ "$no_tunnel" == "true" ]]; then
        # Temporarily unset token to skip tunnel
        local saved_token="${CLOUDFLARE_TUNNEL_TOKEN:-}"
        unset CLOUDFLARE_TUNNEL_TOKEN
        start_services
        export CLOUDFLARE_TUNNEL_TOKEN="$saved_token"
    else
        start_services
    fi

    verify_deployment
}

main "$@"
