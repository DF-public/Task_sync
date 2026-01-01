# System Architecture

> **Status:** Placeholder - Full documentation coming in Phase 2

## Overview

Unified Task Sync uses a layered architecture to provide secure, automated task synchronization across multiple project management systems.

## Components

### 1. Presentation Layer
- **Vikunja Web UI** - Browser-based task management interface
- Accessible at `http://localhost:3456` (configurable)

### 2. Application Layer
- **Vikunja API** - RESTful API for task operations
- **Claude Code CLI** - Automation orchestration
- **MCP Servers** - Protocol adapters for external systems

### 3. Data Layer
- **MariaDB** - Persistent storage for tasks, projects, and users
- **Docker Volumes** - File attachments and database persistence

### 4. Integration Layer
- **YouTrack MCP** - Read tasks from YouTrack instances
- **Atlassian MCP** - Read tasks from Jira/Confluence

## Data Flow

```
[YouTrack] ──┐
             │ MCP Protocol
[Jira] ──────┼──────────────> [Claude Code] ────> [Vikunja API] ────> [MariaDB]
             │                     │
[Future] ────┘                     │
                                   v
                           [Sync Logs/Audit]
```

## Security Boundaries

| Boundary | Protection |
|----------|------------|
| External APIs | Read-only tokens, HTTPS |
| Internal Network | Docker bridge network |
| Database | Not exposed to host |
| Secrets | Environment variables only |

## Detailed Documentation

*Coming in Phase 2:*
- Sequence diagrams for sync operations
- API endpoint documentation
- MCP server configuration guide
- Troubleshooting flowcharts
