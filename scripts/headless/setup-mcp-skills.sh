#!/usr/bin/env bash
# =============================================================================
# Setup MCP Server and Install Skill Templates
# =============================================================================
# Purpose: Configure MCP server and install skill templates for headless
#          Claude Code operation with Todoist/Vikunja integration.
#
# Usage:
#   ./setup-mcp-skills.sh
#
# Environment Variables:
#   VIKUNJA_URL       - Vikunja API URL
#   VIKUNJA_TOKEN     - Vikunja API token
#   TODOIST_API_TOKEN - Todoist API token
#
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="${LOG_DIR:-/var/log/claude-code}"
LOG_FILE="${LOG_DIR}/mcp-setup-$(date +%Y%m%d-%H%M%S).log"
SKILLS_DIR="${SKILLS_DIR:-/mnt/skills/user}"
MCP_CONFIG_FILE="${HOME}/.config/claude-code/mcp.json"
STATE_DIR="${HOME}/sync-state"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp
    timestamp=$(date +'%Y-%m-%d %H:%M:%S')

    # Console output with colors
    case "$level" in
        INFO)  echo -e "${BLUE}[INFO]${NC} $message" ;;
        OK)    echo -e "${GREEN}[OK]${NC} $message" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $message" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" ;;
    esac

    # File logging
    if [[ -d "$LOG_DIR" ]] || mkdir -p "$LOG_DIR" 2>/dev/null; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    fi
}

# -----------------------------------------------------------------------------
# Main Setup
# -----------------------------------------------------------------------------

log "INFO" "Starting MCP server and skills setup"

# Create necessary directories
mkdir -p "$SKILLS_DIR" 2>/dev/null || true
mkdir -p "$STATE_DIR"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
mkdir -p "$(dirname "$MCP_CONFIG_FILE")"

log "INFO" "Created directory structure"

# Create MCP configuration
log "INFO" "Creating MCP configuration file"

cat > "$MCP_CONFIG_FILE" <<'EOF'
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
        "VIKUNJA_API_URL": "${VIKUNJA_API_URL:-http://vikunja:3456/api/v1}",
        "VIKUNJA_API_TOKEN": "${VIKUNJA_API_TOKEN}"
      }
    },
    "todoist": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-todoist"
      ],
      "env": {
        "TODOIST_API_TOKEN": "${TODOIST_API_TOKEN}"
      }
    }
  }
}
EOF

log "OK" "MCP configuration created at $MCP_CONFIG_FILE"

# Copy skill templates if SKILLS_DIR is writable
if [[ -w "$SKILLS_DIR" ]] || [[ -w "$(dirname "$SKILLS_DIR")" ]]; then
    log "INFO" "Installing skill templates to $SKILLS_DIR"

    if [[ -d "$PROJECT_ROOT/skills" ]]; then
        cp "$PROJECT_ROOT/skills/task-import.md" "$SKILLS_DIR/" 2>/dev/null || true
        cp "$PROJECT_ROOT/skills/task-export.md" "$SKILLS_DIR/" 2>/dev/null || true
        log "OK" "Skill templates installed"
    else
        log "WARN" "Skills directory not found at $PROJECT_ROOT/skills"
    fi
else
    log "WARN" "Skills directory not writable: $SKILLS_DIR"
    log "INFO" "Skills remain at: $PROJECT_ROOT/skills/"
fi

# Initialize sync state files
log "INFO" "Initializing sync state files"

cat > "$STATE_DIR/sync-state.json" <<'EOF'
{
  "last_import": null,
  "last_export": null,
  "task_count": 0,
  "project_count": 0,
  "pending_exports": []
}
EOF

cat > "$STATE_DIR/pending-exports.json" <<'EOF'
[]
EOF

log "OK" "Sync state files initialized"

# Validate MCP configuration
log "INFO" "Validating MCP configuration"

if command -v jq &> /dev/null; then
    if jq empty "$MCP_CONFIG_FILE" 2>/dev/null; then
        log "OK" "MCP configuration is valid JSON"
    else
        log "ERROR" "MCP configuration is invalid JSON"
        exit 1
    fi
else
    log "WARN" "jq not installed, skipping JSON validation"
fi

# Set permissions
chmod 644 "$MCP_CONFIG_FILE"
chmod 644 "$STATE_DIR"/*.json

log "OK" "Set file permissions"

# Summary
log "INFO" "============================================"
log "INFO" "Setup completed successfully"
log "INFO" "============================================"
log "INFO" "MCP Config: $MCP_CONFIG_FILE"
log "INFO" "Skills: $PROJECT_ROOT/skills/"
log "INFO" "State: $STATE_DIR/"
log "INFO" "Logs: $LOG_FILE"
log "INFO" ""
log "INFO" "Next steps:"
log "INFO" "1. Set environment variables (VIKUNJA_API_TOKEN, TODOIST_API_TOKEN)"
log "INFO" "2. Run: docker compose up -d vikunja-mcp"
log "INFO" "3. Test with: claude /mcp"
