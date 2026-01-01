#!/usr/bin/env bash
# =============================================================================
# Setup Logging for Claude Code Headless Operations
# =============================================================================
# Purpose: Configure comprehensive logging for all sync operations including
#          logrotate for automatic log management.
#
# Usage:
#   sudo ./setup-logging.sh
#
# Creates:
#   - /var/log/claude-code/ directory
#   - Logrotate configuration
#   - Optional rsyslog configuration
#
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

LOG_DIR="/var/log/claude-code"
LOGROTATE_CONF="/etc/logrotate.d/claude-code"
RSYSLOG_CONF="/etc/rsyslog.d/50-claude-code.conf"
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

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        log_warn "Not running as root - some operations may fail"
        log_info "For full setup, run: sudo $0"
    fi
}

# -----------------------------------------------------------------------------
# Main Setup
# -----------------------------------------------------------------------------

log_info "Setting up logging for Claude Code..."

check_root

# Create log directory
log_info "Creating log directory..."
mkdir -p "$LOG_DIR"

# Set ownership (try, but don't fail if not root)
if [[ "$EUID" -eq 0 ]]; then
    chown "$CLAUDE_USER:$CLAUDE_USER" "$LOG_DIR"
    chmod 755 "$LOG_DIR"
    log_ok "Log directory created with proper permissions"
else
    chmod 755 "$LOG_DIR" 2>/dev/null || true
    log_ok "Log directory created"
fi

# Configure logrotate
if [[ "$EUID" -eq 0 ]] && [[ -d "/etc/logrotate.d" ]]; then
    log_info "Configuring logrotate..."

    cat > "$LOGROTATE_CONF" <<EOF
# Claude Code log rotation
# Rotate daily, keep 30 days, compress old logs

$LOG_DIR/*.log {
    daily
    rotate 30
    compress
    delaycompress
    notifempty
    missingok
    create 0644 $CLAUDE_USER $CLAUDE_USER
    sharedscripts
    postrotate
        # Signal rsyslog to reopen log files if it's running
        systemctl reload rsyslog > /dev/null 2>&1 || true
    endscript
}
EOF

    chmod 644 "$LOGROTATE_CONF"
    log_ok "Logrotate configured at $LOGROTATE_CONF"
else
    log_warn "Skipping logrotate setup (requires root)"
fi

# Configure rsyslog (optional)
if [[ "$EUID" -eq 0 ]] && [[ -d "/etc/rsyslog.d" ]]; then
    log_info "Configuring rsyslog..."

    cat > "$RSYSLOG_CONF" <<EOF
# Claude Code syslog configuration
# Capture logs from claude-code tagged messages

# Direct claude-code messages to dedicated log
:programname, isequal, "claude-code" $LOG_DIR/syslog.log
& stop

# Also capture cron job output
:programname, isequal, "CRON" $LOG_DIR/cron-syslog.log
EOF

    chmod 644 "$RSYSLOG_CONF"

    # Restart rsyslog if available
    if systemctl is-active rsyslog > /dev/null 2>&1; then
        systemctl restart rsyslog
        log_ok "rsyslog restarted with new configuration"
    else
        log_warn "rsyslog not running, configuration saved for later"
    fi
else
    log_warn "Skipping rsyslog setup (requires root or rsyslog not installed)"
fi

# Create initial log files
log_info "Creating initial log files..."
touch "$LOG_DIR/import.log" "$LOG_DIR/export.log" "$LOG_DIR/cron.log" 2>/dev/null || true

if [[ "$EUID" -eq 0 ]]; then
    chown "$CLAUDE_USER:$CLAUDE_USER" "$LOG_DIR"/*.log 2>/dev/null || true
fi

log_ok "Initial log files created"

# Summary
echo ""
log_ok "============================================"
log_ok "Logging setup completed"
log_ok "============================================"
echo ""
echo "Log directory: $LOG_DIR"
echo ""
echo "Log files:"
echo "  - import-YYYYMMDD.log  : Task import logs"
echo "  - export-YYYYMMDD.log  : Status export logs"
echo "  - cron.log             : Cron job output"
echo "  - syslog.log           : System log messages"
echo ""
echo "View logs:"
echo "  tail -f $LOG_DIR/import-\$(date +%Y%m%d).log"
echo "  tail -f $LOG_DIR/export-\$(date +%Y%m%d).log"
echo ""
if [[ -f "$LOGROTATE_CONF" ]]; then
    echo "Logrotate: $LOGROTATE_CONF (30 day retention)"
fi
