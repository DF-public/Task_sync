# SKILL: Task Status Export to External Sources

## Purpose

Export task status changes back to Todoist/Vikunja for bidirectional sync.

## Overview

This skill handles exporting task status changes (completion, updates) from Claude's working context back to external task management systems, ensuring bidirectional synchronization.

## When to Use

- After Claude completes tasks on user's behalf
- After bulk status updates or task processing
- Scheduled sync (every 2 hours during daytime)
- When user explicitly requests sync

## Core Capabilities

1. **Status Updates**: Mark tasks as complete/incomplete
2. **Priority Changes**: Update task priority levels
3. **Due Date Updates**: Modify task deadlines
4. **Comment Addition**: Add completion notes or context
5. **Batch Operations**: Handle multiple updates efficiently

## Usage

```bash
export_status [--source todoist|vikunja] [--dry-run]
```

## Export Strategy

### Status-Only Export (Primary Use Case)

1. Read pending changes from state file
2. Group changes by operation type (complete, update)
3. Execute batch operations via MCP
4. Verify each operation succeeded
5. Update sync state
6. Log all changes with timestamps

### Change Detection

1. Compare current task state with last import
2. Identify tasks marked as complete
3. Identify tasks with updated fields
4. Create change list with operation type
5. Filter out already-synced changes

## Supported Operations

### Complete Tasks

```javascript
// Batch complete tasks
await todoist.complete_tasks({
  ids: ["task_1", "task_2", "task_3"]
});
```

### Update Task Status

```javascript
// Update individual task
await todoist.update_tasks({
  tasks: [{
    id: "task_1",
    status: "completed"
  }]
});
```

### Add Completion Comment

```javascript
// Add context to completed task
await todoist.add_comments({
  comments: [{
    taskId: "task_1",
    content: "Completed automatically by Claude Code sync"
  }]
});
```

## Change Tracking

### Change Record Format

```json
{
  "task_id": "task_12345",
  "operation": "complete",
  "timestamp": "2026-01-01T14:30:00Z",
  "status": "pending",
  "retry_count": 0,
  "error": null
}
```

### State Files

- Pending changes: `/home/claude/sync-state/pending-exports.json`
- Failed exports: `/home/claude/sync-state/failed-exports.json`

## Error Handling

```
1. Attempt export operation
2. If fails:
   - Log error with full context
   - Increment retry counter
   - If retry_count < 3: Keep in pending queue
   - If retry_count >= 3: Move to failed queue, alert
3. If succeeds:
   - Remove from pending queue
   - Add to success log
   - Update sync timestamp
```

## Conflict Resolution

| Scenario | Resolution |
|----------|------------|
| Task Already Completed | Skip, log warning |
| Task Not Found | Log error, mark as failed |
| Concurrent Modifications | Last write wins (export overwrites) |
| Network Failures | Retry up to 3 times |

## Logging Format

### Success Log

```
[EXPORT] Started: Status sync to Todoist
[EXPORT] Completed 5 tasks: task_1, task_2, task_3, task_4, task_5
[EXPORT] Updated 2 priorities: task_6 (p2->p1), task_7 (p3->p2)
[EXPORT] All changes synced successfully
[EXPORT] Completed in 1.8s
```

### Error Log

```
[EXPORT] ERROR: Failed to complete task_8: 404 Not Found
[EXPORT] ERROR: Rate limit hit, will retry in 60s
[EXPORT] WARNING: Task task_9 already completed, skipping
```

## Rollback Strategy

- **No Automatic Rollback**: Export operations are one-way
- **Manual Intervention**: Failed exports logged for manual review
- **Idempotent Operations**: Safe to retry without side effects

## Performance Optimization

| Optimization | Implementation |
|--------------|----------------|
| Batch Operations | Use batch APIs when available (up to 50 items) |
| Rate Limiting | Respect API rate limits (max 1 req/sec) |
| Parallel Execution | Export to multiple sources concurrently |
| Change Deduplication | Remove duplicate changes before export |

## Related Skills

- [task-import.md](./task-import.md) - Import tasks from external sources
