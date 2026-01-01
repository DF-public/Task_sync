#!/usr/bin/env bash
# =============================================================================
# Import Tasks from Todoist/Vikunja via Claude Code
# =============================================================================
# Purpose: Automated task import for headless Claude Code operation.
#          Runs hourly via cron to keep local state synchronized.
#
# Usage:
#   ./import-tasks.sh [--source todoist|vikunja|all] [--mode full|incremental]
#
# Environment Variables:
#   VIKUNJA_API_URL     - Vikunja API URL
#   VIKUNJA_API_TOKEN   - Vikunja API token
#   TODOIST_API_TOKEN   - Todoist API token
#
# Cron Entry:
#   0 * * * * /path/to/import-tasks.sh >> /var/log/claude-code/cron.log 2>&1
#
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="${LOG_DIR:-/var/log/claude-code}"
LOG_FILE="${LOG_DIR}/import-$(date +%Y%m%d).log"
STATE_DIR="${STATE_DIR:-$HOME/sync-state}"
STATE_FILE="${STATE_DIR}/sync-state.json"
IMPORT_FILE="${STATE_DIR}/import-$(date +%Y%m%d-%H%M%S).json"
CLAUDE_CODE_BIN="${CLAUDE_CODE_BIN:-claude}"
MAX_RETRIES=3
RETRY_DELAY=10

# Defaults
SOURCE="all"
MODE="auto"

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
        INFO)  echo -e "${BLUE}[INFO]${NC} [IMPORT] $message" ;;
        OK)    echo -e "${GREEN}[OK]${NC} [IMPORT] $message" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} [IMPORT] $message" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} [IMPORT] $message" ;;
        DEBUG) [[ "${VERBOSE:-false}" == "true" ]] && echo "[DEBUG] [IMPORT] $message" ;;
    esac

    # File logging
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    echo "[$timestamp] [$level] [IMPORT] $message" >> "$LOG_FILE"
}

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

ensure_state_dir() {
    if [[ ! -d "$STATE_DIR" ]]; then
        mkdir -p "$STATE_DIR"
        log "INFO" "Created state directory: $STATE_DIR"
    fi

    if [[ ! -f "$STATE_FILE" ]]; then
        echo '{"last_import": null, "task_count": 0, "project_count": 0}' > "$STATE_FILE"
        log "INFO" "Initialized state file: $STATE_FILE"
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

import_from_vikunja() {
    log "INFO" "Importing from Vikunja..."

    if [[ -z "${VIKUNJA_API_TOKEN:-}" ]]; then
        log "WARN" "VIKUNJA_API_TOKEN not set, skipping Vikunja import"
        return 0
    fi

    local api_url="${VIKUNJA_API_URL:-http://localhost:3456/api/v1}"
    local temp_file="/tmp/vikunja-import-$$.json"

    # Fetch projects
    log "INFO" "Fetching projects..."
    local projects
    projects=$(curl -sf -H "Authorization: Bearer ${VIKUNJA_API_TOKEN}" \
        "${api_url}/projects" 2>/dev/null) || {
        log "ERROR" "Failed to fetch projects from Vikunja"
        return 1
    }

    local project_count
    project_count=$(echo "$projects" | jq 'length')
    log "INFO" "Found $project_count projects"

    # Fetch tasks
    log "INFO" "Fetching tasks..."
    local tasks
    tasks=$(curl -sf -H "Authorization: Bearer ${VIKUNJA_API_TOKEN}" \
        "${api_url}/tasks/all" 2>/dev/null) || {
        log "ERROR" "Failed to fetch tasks from Vikunja"
        return 1
    }

    local task_count
    task_count=$(echo "$tasks" | jq 'length')
    log "INFO" "Found $task_count tasks"

    # Combine into import file
    jq -n \
        --argjson projects "$projects" \
        --argjson tasks "$tasks" \
        --arg source "vikunja" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            source: $source,
            timestamp: $timestamp,
            projects: $projects,
            tasks: $tasks
        }' > "$temp_file"

    echo "$temp_file"
}

import_from_todoist() {
    log "INFO" "Importing from Todoist..."

    if [[ -z "${TODOIST_API_TOKEN:-}" ]]; then
        log "WARN" "TODOIST_API_TOKEN not set, skipping Todoist import"
        return 0
    fi

    local temp_file="/tmp/todoist-import-$$.json"

    # Fetch projects
    log "INFO" "Fetching projects..."
    local projects
    projects=$(curl -sf -H "Authorization: Bearer ${TODOIST_API_TOKEN}" \
        "https://api.todoist.com/rest/v2/projects" 2>/dev/null) || {
        log "ERROR" "Failed to fetch projects from Todoist"
        return 1
    }

    local project_count
    project_count=$(echo "$projects" | jq 'length')
    log "INFO" "Found $project_count projects"

    # Fetch tasks
    log "INFO" "Fetching tasks..."
    local tasks
    tasks=$(curl -sf -H "Authorization: Bearer ${TODOIST_API_TOKEN}" \
        "https://api.todoist.com/rest/v2/tasks" 2>/dev/null) || {
        log "ERROR" "Failed to fetch tasks from Todoist"
        return 1
    }

    local task_count
    task_count=$(echo "$tasks" | jq 'length')
    log "INFO" "Found $task_count tasks"

    # Combine into import file
    jq -n \
        --argjson projects "$projects" \
        --argjson tasks "$tasks" \
        --arg source "todoist" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            source: $source,
            timestamp: $timestamp,
            projects: $projects,
            tasks: $tasks
        }' > "$temp_file"

    echo "$temp_file"
}

merge_imports() {
    local output_file="$1"
    shift
    local input_files=("$@")

    log "INFO" "Merging ${#input_files[@]} import files..."

    # Start with empty structure
    local merged='{"sources": [], "projects": [], "tasks": [], "timestamp": ""}'
    merged=$(echo "$merged" | jq --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '.timestamp = $ts')

    for file in "${input_files[@]}"; do
        if [[ -f "$file" ]]; then
            local source
            source=$(jq -r '.source' "$file")
            merged=$(echo "$merged" | jq --arg src "$source" '.sources += [$src]')
            merged=$(echo "$merged" | jq --slurpfile data "$file" '.projects += $data[0].projects | .tasks += $data[0].tasks')
            rm -f "$file"
        fi
    done

    echo "$merged" > "$output_file"
    log "OK" "Merged imports saved to: $output_file"
}

update_state() {
    local import_file="$1"

    local task_count project_count
    task_count=$(jq '.tasks | length' "$import_file")
    project_count=$(jq '.projects | length' "$import_file")

    jq --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       --argjson tasks "$task_count" \
       --argjson projects "$project_count" \
       '.last_import = $timestamp | .task_count = $tasks | .project_count = $projects' \
       "$STATE_FILE" > "${STATE_FILE}.tmp"
    mv "${STATE_FILE}.tmp" "$STATE_FILE"

    log "OK" "State updated: $task_count tasks, $project_count projects"
}

cleanup_old_imports() {
    log "INFO" "Cleaning up old import files..."
    find "$STATE_DIR" -name "import-*.json" -mtime +7 -delete 2>/dev/null || true
}

show_help() {
    cat << EOF
Import Tasks from Todoist/Vikunja

Usage: $(basename "$0") [OPTIONS]

Options:
    --source SOURCE    Import source: todoist, vikunja, all (default: all)
    --mode MODE        Import mode: full, incremental, auto (default: auto)
    --verbose          Enable verbose output
    -h, --help         Show this help

Environment Variables:
    VIKUNJA_API_URL     Vikunja API URL
    VIKUNJA_API_TOKEN   Vikunja API token
    TODOIST_API_TOKEN   Todoist API token

Examples:
    # Import from all sources
    ./$(basename "$0")

    # Import only from Todoist
    ./$(basename "$0") --source todoist

    # Force full import
    ./$(basename "$0") --mode full --verbose
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
            --mode)
                MODE="$2"
                shift 2
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

    log "INFO" "========== Import Task Started =========="
    log "INFO" "Source: $SOURCE"
    log "INFO" "Mode: $MODE"

    check_dependencies
    ensure_state_dir

    # Determine import mode
    local last_import
    last_import=$(jq -r '.last_import // "null"' "$STATE_FILE")

    if [[ "$MODE" == "auto" ]]; then
        if [[ "$last_import" == "null" ]]; then
            MODE="full"
            log "INFO" "First import detected, using FULL mode"
        else
            MODE="incremental"
            log "INFO" "Using INCREMENTAL mode since $last_import"
        fi
    fi

    # Perform imports
    local import_files=()

    case "$SOURCE" in
        vikunja)
            result=$(import_from_vikunja) && import_files+=("$result")
            ;;
        todoist)
            result=$(import_from_todoist) && import_files+=("$result")
            ;;
        all)
            result=$(import_from_vikunja) && [[ -n "$result" ]] && import_files+=("$result")
            result=$(import_from_todoist) && [[ -n "$result" ]] && import_files+=("$result")
            ;;
        *)
            log "ERROR" "Unknown source: $SOURCE"
            exit 1
            ;;
    esac

    if [[ ${#import_files[@]} -eq 0 ]]; then
        log "WARN" "No data imported from any source"
        exit 0
    fi

    # Merge and save
    merge_imports "$IMPORT_FILE" "${import_files[@]}"
    update_state "$IMPORT_FILE"
    cleanup_old_imports

    log "INFO" "========== Import Task Completed =========="
}

main "$@"
