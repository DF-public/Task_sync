#!/usr/bin/env bash
# =============================================================================
# Export Task Status Updates to Todoist/Vikunja
# =============================================================================
# Purpose: Export task status changes back to external systems.
#          Runs every 2 hours during daytime via cron.
#
# Usage:
#   ./export-status.sh [--source todoist|vikunja|all] [--dry-run]
#
# Environment Variables:
#   VIKUNJA_API_URL     - Vikunja API URL
#   VIKUNJA_API_TOKEN   - Vikunja API token
#   TODOIST_API_TOKEN   - Todoist API token
#
# Cron Entry:
#   0 8-20/2 * * * /path/to/export-status.sh >> /var/log/claude-code/cron.log 2>&1
#
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="${LOG_DIR:-/var/log/claude-code}"
LOG_FILE="${LOG_DIR}/export-$(date +%Y%m%d).log"
STATE_DIR="${STATE_DIR:-$HOME/sync-state}"
STATE_FILE="${STATE_DIR}/sync-state.json"
PENDING_FILE="${STATE_DIR}/pending-exports.json"
FAILED_FILE="${STATE_DIR}/failed-exports.json"
MAX_RETRIES=3
BATCH_SIZE=50

# Defaults
SOURCE="all"
DRY_RUN=false

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

    # Console output
    case "$level" in
        INFO)  echo -e "${BLUE}[INFO]${NC} [EXPORT] $message" ;;
        OK)    echo -e "${GREEN}[OK]${NC} [EXPORT] $message" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} [EXPORT] $message" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} [EXPORT] $message" ;;
        DEBUG) [[ "${VERBOSE:-false}" == "true" ]] && echo "[DEBUG] [EXPORT] $message" ;;
    esac

    # File logging
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    echo "[$timestamp] [$level] [EXPORT] $message" >> "$LOG_FILE"
}

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

ensure_state_files() {
    mkdir -p "$STATE_DIR" 2>/dev/null || true

    if [[ ! -f "$PENDING_FILE" ]]; then
        echo "[]" > "$PENDING_FILE"
    fi

    if [[ ! -f "$FAILED_FILE" ]]; then
        echo "[]" > "$FAILED_FILE"
    fi
}

check_dependencies() {
    local missing=()

    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi

    if ! command -v curl &> /dev/null; then
        missing+=("curl")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log "ERROR" "Missing dependencies: ${missing[*]}"
        exit 1
    fi
}

export_to_vikunja() {
    local task_id="$1"
    local operation="$2"

    if [[ -z "${VIKUNJA_API_TOKEN:-}" ]]; then
        log "WARN" "VIKUNJA_API_TOKEN not set"
        return 1
    fi

    local api_url="${VIKUNJA_API_URL:-http://localhost:3456/api/v1}"

    case "$operation" in
        complete)
            if [[ "$DRY_RUN" == "true" ]]; then
                log "INFO" "[DRY RUN] Would complete task $task_id in Vikunja"
                return 0
            fi

            # Get current task, set done=true, update
            local task
            task=$(curl -sf -H "Authorization: Bearer ${VIKUNJA_API_TOKEN}" \
                "${api_url}/tasks/${task_id}" 2>/dev/null) || {
                log "ERROR" "Failed to fetch task $task_id"
                return 1
            }

            local updated_task
            updated_task=$(echo "$task" | jq '.done = true')

            curl -sf -X POST \
                -H "Authorization: Bearer ${VIKUNJA_API_TOKEN}" \
                -H "Content-Type: application/json" \
                -d "$updated_task" \
                "${api_url}/tasks/${task_id}" > /dev/null 2>&1 || {
                log "ERROR" "Failed to complete task $task_id"
                return 1
            }

            log "OK" "Completed task $task_id in Vikunja"
            ;;

        *)
            log "WARN" "Unknown operation: $operation"
            return 1
            ;;
    esac
}

export_to_todoist() {
    local task_id="$1"
    local operation="$2"

    if [[ -z "${TODOIST_API_TOKEN:-}" ]]; then
        log "WARN" "TODOIST_API_TOKEN not set"
        return 1
    fi

    case "$operation" in
        complete)
            if [[ "$DRY_RUN" == "true" ]]; then
                log "INFO" "[DRY RUN] Would complete task $task_id in Todoist"
                return 0
            fi

            curl -sf -X POST \
                -H "Authorization: Bearer ${TODOIST_API_TOKEN}" \
                "https://api.todoist.com/rest/v2/tasks/${task_id}/close" > /dev/null 2>&1 || {
                log "ERROR" "Failed to complete task $task_id in Todoist"
                return 1
            }

            log "OK" "Completed task $task_id in Todoist"
            ;;

        *)
            log "WARN" "Unknown operation: $operation"
            return 1
            ;;
    esac
}

process_pending_exports() {
    local pending_count
    pending_count=$(jq 'length' "$PENDING_FILE")

    if [[ "$pending_count" -eq 0 ]]; then
        log "INFO" "No pending exports"
        return 0
    fi

    log "INFO" "Processing $pending_count pending exports"

    local completed=()
    local failed=()
    local remaining=()

    # Process each pending export
    while read -r export_item; do
        local task_id operation source retry_count
        task_id=$(echo "$export_item" | jq -r '.task_id')
        operation=$(echo "$export_item" | jq -r '.operation')
        source=$(echo "$export_item" | jq -r '.source // "vikunja"')
        retry_count=$(echo "$export_item" | jq -r '.retry_count // 0')

        log "INFO" "Processing: $task_id ($operation) from $source"

        local success=false

        case "$source" in
            vikunja)
                if export_to_vikunja "$task_id" "$operation"; then
                    success=true
                fi
                ;;
            todoist)
                if export_to_todoist "$task_id" "$operation"; then
                    success=true
                fi
                ;;
            *)
                log "WARN" "Unknown source: $source"
                ;;
        esac

        if [[ "$success" == "true" ]]; then
            completed+=("$task_id")
        else
            retry_count=$((retry_count + 1))
            if [[ "$retry_count" -ge "$MAX_RETRIES" ]]; then
                log "ERROR" "Task $task_id failed after $MAX_RETRIES retries, moving to failed"
                failed+=("$(echo "$export_item" | jq --argjson rc "$retry_count" '.retry_count = $rc')")
            else
                log "WARN" "Task $task_id failed, retry $retry_count of $MAX_RETRIES"
                remaining+=("$(echo "$export_item" | jq --argjson rc "$retry_count" '.retry_count = $rc')")
            fi
        fi
    done < <(jq -c '.[]' "$PENDING_FILE")

    # Update pending file with remaining items
    printf '%s\n' "${remaining[@]:-}" | jq -s '.' > "$PENDING_FILE"

    # Add failed items to failed file
    if [[ ${#failed[@]} -gt 0 ]]; then
        local current_failed
        current_failed=$(cat "$FAILED_FILE")
        printf '%s\n' "${failed[@]}" | jq -s ". + $current_failed" > "$FAILED_FILE"
    fi

    log "OK" "Completed: ${#completed[@]}, Failed: ${#failed[@]}, Remaining: ${#remaining[@]}"
}

update_state() {
    jq --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.last_export = $timestamp' \
       "$STATE_FILE" > "${STATE_FILE}.tmp"
    mv "${STATE_FILE}.tmp" "$STATE_FILE"

    log "OK" "Updated export timestamp in state file"
}

show_help() {
    cat << EOF
Export Task Status Updates

Usage: $(basename "$0") [OPTIONS]

Options:
    --source SOURCE    Export target: todoist, vikunja, all (default: all)
    --dry-run          Show what would be exported without making changes
    --verbose          Enable verbose output
    -h, --help         Show this help

Environment Variables:
    VIKUNJA_API_URL     Vikunja API URL
    VIKUNJA_API_TOKEN   Vikunja API token
    TODOIST_API_TOKEN   Todoist API token

Pending Exports File:
    $PENDING_FILE

Add exports by appending to the pending file:
    {
      "task_id": "123",
      "operation": "complete",
      "source": "vikunja"
    }

Examples:
    # Process all pending exports
    ./$(basename "$0")

    # Dry run
    ./$(basename "$0") --dry-run

    # Export only to Todoist
    ./$(basename "$0") --source todoist
EOF
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --source)
                SOURCE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    log "INFO" "========== Export Status Started =========="
    [[ "$DRY_RUN" == "true" ]] && log "WARN" "DRY RUN MODE - No changes will be made"

    check_dependencies
    ensure_state_files

    process_pending_exports

    if [[ "$DRY_RUN" != "true" ]]; then
        update_state
    fi

    # Report on accumulated failed exports
    if [[ -f "$FAILED_FILE" ]]; then
        local total_failed
        total_failed=$(jq 'length' "$FAILED_FILE")
        if [[ "$total_failed" -gt 0 ]]; then
            log "WARN" "Total accumulated failed exports: $total_failed"
            log "WARN" "Manual review required: $FAILED_FILE"
        fi
    fi

    log "INFO" "========== Export Status Completed =========="
}

main "$@"
