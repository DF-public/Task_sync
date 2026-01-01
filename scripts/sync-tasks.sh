#!/usr/bin/env bash
# =============================================================================
# Task Synchronization Script
# =============================================================================
# This script synchronizes tasks between external systems (YouTrack, Jira)
# and Vikunja using the configured APIs.
#
# Usage:
#   ./sync-tasks.sh [--source SOURCE] [--dry-run]
#
# Options:
#   --source SOURCE   Sync from specific source (youtrack, jira, all)
#   --dry-run         Show what would be synced without making changes
#   --verbose         Enable verbose output
#
# Environment Variables:
#   VIKUNJA_API_URL       Vikunja API URL
#   VIKUNJA_API_TOKEN     Vikunja API token
#   YOUTRACK_URL          YouTrack base URL
#   YOUTRACK_TOKEN        YouTrack API token
#   JIRA_URL              Jira base URL
#   JIRA_EMAIL            Jira user email
#   JIRA_TOKEN            Jira API token
#
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_DIR="${LOG_DIR:-/var/log/sync}"
LOG_FILE="${LOG_DIR}/sync-$(date +%Y%m%d).log"

# Defaults
DRY_RUN=false
VERBOSE=false
SOURCE="all"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Sync mode: titles_only (default) or full
SYNC_MODE="${SYNC_MODE:-titles_only}"

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Console output with colors
    case "$level" in
        INFO)  echo -e "${BLUE}[INFO]${NC} $message" ;;
        OK)    echo -e "${GREEN}[OK]${NC} $message" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $message" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" ;;
        DEBUG) [[ "$VERBOSE" == "true" ]] && echo -e "[DEBUG] $message" ;;
    esac

    # File logging
    if [[ -d "$LOG_DIR" ]]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    fi
}

check_dependencies() {
    log INFO "Checking dependencies..."

    local missing=()

    if ! command -v curl &> /dev/null; then
        missing+=("curl")
    fi

    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log ERROR "Missing dependencies: ${missing[*]}"
        log INFO "Install with: apk add ${missing[*]}"
        exit 1
    fi

    log OK "Dependencies satisfied"
}

validate_config() {
    log INFO "Validating configuration..."

    local valid=true

    # Check Vikunja config
    if [[ -z "${VIKUNJA_API_URL:-}" ]]; then
        log ERROR "VIKUNJA_API_URL not set"
        valid=false
    fi

    if [[ -z "${VIKUNJA_API_TOKEN:-}" ]]; then
        log ERROR "VIKUNJA_API_TOKEN not set"
        valid=false
    fi

    # Check source-specific config
    if [[ "$SOURCE" == "youtrack" ]] || [[ "$SOURCE" == "all" ]]; then
        if [[ -n "${YOUTRACK_URL:-}" ]] && [[ -z "${YOUTRACK_TOKEN:-}" ]]; then
            log WARN "YOUTRACK_URL set but YOUTRACK_TOKEN missing"
        fi
    fi

    if [[ "$SOURCE" == "jira" ]] || [[ "$SOURCE" == "all" ]]; then
        if [[ -n "${JIRA_URL:-}" ]] && [[ -z "${JIRA_TOKEN:-}" ]]; then
            log WARN "JIRA_URL set but JIRA_TOKEN missing"
        fi
    fi

    if [[ "$valid" == "false" ]]; then
        exit 1
    fi

    log OK "Configuration valid"
}

# -----------------------------------------------------------------------------
# Vikunja API Functions
# -----------------------------------------------------------------------------

vikunja_request() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"

    local url="${VIKUNJA_API_URL}${endpoint}"
    local args=(-s -X "$method")
    args+=(-H "Authorization: Bearer ${VIKUNJA_API_TOKEN}")
    args+=(-H "Content-Type: application/json")

    if [[ -n "$data" ]]; then
        args+=(-d "$data")
    fi

    curl "${args[@]}" "$url"
}

get_or_create_project() {
    local project_name="$1"

    # List existing projects
    local projects
    projects=$(vikunja_request GET "/projects")

    # Check if project exists
    local project_id
    project_id=$(echo "$projects" | jq -r ".[] | select(.title == \"$project_name\") | .id" | head -1)

    if [[ -n "$project_id" ]] && [[ "$project_id" != "null" ]]; then
        log DEBUG "Found existing project: $project_name (ID: $project_id)"
        echo "$project_id"
        return
    fi

    # Create project
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create project: $project_name"
        echo "dry-run-id"
        return
    fi

    log INFO "Creating project: $project_name"
    local result
    result=$(vikunja_request PUT "/projects" "{\"title\": \"$project_name\"}")
    echo "$result" | jq -r '.id'
}

create_or_update_task() {
    local project_id="$1"
    local title="$2"
    local external_id="$3"
    local source="$4"

    # Search for existing task with this external ID in title
    local search_term="[${source}:${external_id}]"
    local existing
    existing=$(vikunja_request GET "/projects/${project_id}/tasks" | \
        jq -r ".[] | select(.title | contains(\"$search_term\")) | .id" | head -1)

    if [[ -n "$existing" ]] && [[ "$existing" != "null" ]]; then
        log DEBUG "Task already exists: $title (ID: $existing)"
        return
    fi

    # Privacy-first: Only sync title, not description
    local task_title
    if [[ "$SYNC_MODE" == "titles_only" ]]; then
        task_title="${title} [${source}:${external_id}]"
    else
        task_title="${title} [${source}:${external_id}]"
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create task: $task_title"
        return
    fi

    log INFO "Creating task: $task_title"
    vikunja_request PUT "/projects/${project_id}/tasks" \
        "{\"title\": \"$task_title\"}" > /dev/null
}

# -----------------------------------------------------------------------------
# YouTrack Sync
# -----------------------------------------------------------------------------

sync_youtrack() {
    if [[ -z "${YOUTRACK_URL:-}" ]] || [[ -z "${YOUTRACK_TOKEN:-}" ]]; then
        log WARN "YouTrack not configured, skipping"
        return
    fi

    log INFO "Syncing from YouTrack..."

    # Get or create Vikunja project for YouTrack tasks
    local project_id
    project_id=$(get_or_create_project "YouTrack Tasks")

    # Fetch issues from YouTrack
    local issues
    issues=$(curl -s -X GET \
        -H "Authorization: Bearer ${YOUTRACK_TOKEN}" \
        -H "Accept: application/json" \
        "${YOUTRACK_URL}/api/issues?fields=idReadable,summary&\$top=100")

    # Check for errors
    if echo "$issues" | jq -e '.error' > /dev/null 2>&1; then
        log ERROR "YouTrack API error: $(echo "$issues" | jq -r '.error')"
        return 1
    fi

    # Process each issue
    local count=0
    while read -r issue; do
        local id summary
        id=$(echo "$issue" | jq -r '.idReadable')
        summary=$(echo "$issue" | jq -r '.summary')

        if [[ -n "$id" ]] && [[ "$id" != "null" ]]; then
            create_or_update_task "$project_id" "$summary" "$id" "YT"
            ((count++))
        fi
    done < <(echo "$issues" | jq -c '.[]')

    log OK "YouTrack sync complete: $count tasks processed"
}

# -----------------------------------------------------------------------------
# Jira Sync
# -----------------------------------------------------------------------------

sync_jira() {
    if [[ -z "${JIRA_URL:-}" ]] || [[ -z "${JIRA_TOKEN:-}" ]] || [[ -z "${JIRA_EMAIL:-}" ]]; then
        log WARN "Jira not configured, skipping"
        return
    fi

    log INFO "Syncing from Jira..."

    # Get or create Vikunja project for Jira tasks
    local project_id
    project_id=$(get_or_create_project "Jira Tasks")

    # Fetch issues assigned to user
    local auth
    auth=$(echo -n "${JIRA_EMAIL}:${JIRA_TOKEN}" | base64)

    local jql="assignee=currentUser() AND resolution=Unresolved"
    local issues
    issues=$(curl -s -X GET \
        -H "Authorization: Basic ${auth}" \
        -H "Accept: application/json" \
        "${JIRA_URL}/rest/api/3/search?jql=$(echo "$jql" | jq -sRr @uri)&fields=key,summary&maxResults=100")

    # Check for errors
    if echo "$issues" | jq -e '.errorMessages' > /dev/null 2>&1; then
        log ERROR "Jira API error: $(echo "$issues" | jq -r '.errorMessages[]')"
        return 1
    fi

    # Process each issue
    local count=0
    while read -r issue; do
        local key summary
        key=$(echo "$issue" | jq -r '.key')
        summary=$(echo "$issue" | jq -r '.fields.summary')

        if [[ -n "$key" ]] && [[ "$key" != "null" ]]; then
            create_or_update_task "$project_id" "$summary" "$key" "JIRA"
            ((count++))
        fi
    done < <(echo "$issues" | jq -c '.issues[]')

    log OK "Jira sync complete: $count tasks processed"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

show_help() {
    cat << EOF
Task Synchronization Script

Usage: $(basename "$0") [OPTIONS]

Options:
    --source SOURCE   Sync from specific source: youtrack, jira, all (default: all)
    --dry-run         Show what would be synced without making changes
    --verbose         Enable verbose output
    -h, --help        Show this help message

Environment Variables:
    VIKUNJA_API_URL     Vikunja API URL
    VIKUNJA_API_TOKEN   Vikunja API token
    YOUTRACK_URL        YouTrack base URL
    YOUTRACK_TOKEN      YouTrack API token
    JIRA_URL            Jira base URL
    JIRA_EMAIL          Jira user email
    JIRA_TOKEN          Jira API token
    SYNC_MODE           titles_only (default) or full

Examples:
    # Sync all sources
    ./$(basename "$0")

    # Dry run
    ./$(basename "$0") --dry-run

    # Sync only YouTrack
    ./$(basename "$0") --source youtrack --verbose
EOF
}

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
                log ERROR "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    echo "=============================================="
    echo "  Task Synchronization"
    echo "  $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=============================================="
    echo ""

    [[ "$DRY_RUN" == "true" ]] && log WARN "DRY RUN MODE - No changes will be made"

    check_dependencies
    validate_config

    # Create log directory if needed
    mkdir -p "$LOG_DIR" 2>/dev/null || true

    case "$SOURCE" in
        youtrack)
            sync_youtrack
            ;;
        jira)
            sync_jira
            ;;
        all)
            sync_youtrack
            sync_jira
            ;;
        *)
            log ERROR "Unknown source: $SOURCE"
            exit 1
            ;;
    esac

    echo ""
    log OK "Sync complete!"
}

main "$@"
