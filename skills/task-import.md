# SKILL: Task Import from External Sources

## Purpose

Import tasks, projects, and metadata from Todoist/Vikunja for analysis and processing.

## Overview

This skill handles importing tasks, projects, and metadata from external task management systems (Todoist, Vikunja) into Claude's working context for analysis, processing, and manipulation.

## When to Use

- User requests to "load tasks", "import from Todoist/Vikunja", "show my tasks"
- Scheduled automated imports via cron
- Before performing any task analysis or bulk operations
- When synchronizing external state with Claude's context

## Core Capabilities

1. **Project Import**: Fetch all projects with hierarchy, sections, and metadata
2. **Task Import**: Retrieve tasks with full details (content, due dates, labels, assignments)
3. **Filter Support**: Import by date range, project, status, priority
4. **Incremental Import**: Fetch only tasks updated since last sync
5. **Relationship Mapping**: Preserve parent-child relationships, section assignments

## Usage

```bash
import_tasks [--source todoist|vikunja] [--mode full|incremental]
```

## Import Strategy

### Full Import (Initial Sync)

1. Fetch all projects and their hierarchy
2. For each project, fetch all sections
3. Fetch all active tasks with filters:
   - Status: active/pending
   - Date range: overdue + next 30 days
   - Include: all metadata (labels, priority, assignments)
4. Store import timestamp for next incremental sync

### Incremental Import (Regular Updates)

1. Read last sync timestamp from state file
2. Fetch only tasks modified since last sync
3. Fetch new projects/sections if any
4. Merge with existing context
5. Update sync timestamp

## Data Structures

### Project Object

```json
{
  "id": "project_id",
  "name": "Project Name",
  "parent_id": null,
  "sections": [
    {
      "id": "section_id",
      "name": "Section Name"
    }
  ],
  "metadata": {
    "is_favorite": false,
    "view_style": "list"
  }
}
```

### Task Object

```json
{
  "id": "task_id",
  "content": "Task title",
  "description": "Detailed description",
  "project_id": "project_id",
  "section_id": "section_id",
  "parent_id": null,
  "due": {
    "date": "2026-01-15",
    "string": "tomorrow at 5pm"
  },
  "priority": "p1",
  "labels": ["urgent", "backend"],
  "assignee": "user_id",
  "status": "active",
  "completed_at": null,
  "created_at": "2026-01-01T10:00:00Z",
  "updated_at": "2026-01-01T12:00:00Z"
}
```

## MCP Tool Usage

### Todoist MCP

```javascript
// Get overview
await todoist.get_overview({ projectId: null });

// Import tasks by date
await todoist.find_tasks_by_date({
  startDate: "today",
  daysCount: 30,
  overdueOption: "include-overdue"
});

// Import projects
await todoist.find_projects({});
```

### Vikunja MCP

```javascript
// Get all projects
await vikunja.listProjects();

// Get tasks with filters
await vikunja.listTasks({
  filter: "done = false",
  sort_by: ["due_date", "priority"]
});
```

## Error Handling

| Error Type | Action |
|------------|--------|
| Network Errors | Retry 3 times with exponential backoff |
| Authentication Errors | Log error, exit with code 1 (requires manual intervention) |
| Rate Limits | Wait and retry after rate limit window |
| Partial Failures | Import what succeeded, log failures, continue |

## Output

Imported data is saved to:

```bash
/home/claude/sync-state/import-$(date +%Y%m%d-%H%M%S).json
```

## Logging Format

```
[IMPORT] Started: Full import from Todoist
[IMPORT] Projects fetched: 12 projects, 45 sections
[IMPORT] Tasks fetched: 234 active tasks
[IMPORT] Date range: 2025-12-01 to 2026-01-31
[IMPORT] Completed in 3.2s
[IMPORT] Saved to: /home/claude/sync-state/import-20260101-120000.json
```

## State Management

Sync state is maintained in:

```json
{
  "last_import": "2026-01-01T12:00:00Z",
  "task_count": 234,
  "project_count": 12,
  "last_task_id": "task_12345"
}
```

## Related Skills

- [task-export.md](./task-export.md) - Export status updates back to source
