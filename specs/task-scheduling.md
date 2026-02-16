# Task Scheduling

Priority-based scheduling with dependency resolution and atomic task claiming for concurrent agents.

## Requirements

- `task next` must return the highest-priority task that is:
  - Status is `open` (not active, done, or deleted)
  - Has no unresolved blockers (all tasks in its `blocked_by` set are `done` or `deleted`)
  - Not assigned to any agent
- Priority ordering: lower number = higher priority (0 before 1 before 2)
- Tiebreaker: `created_at` ascending (oldest first)
- `task claim <id> <agent-id>` must be a single atomic transaction that:
  1. Verifies the task status is `open`
  2. Verifies the task has no unresolved blockers
  3. Sets status to `active` and assignee to the agent ID
  4. Updates `updated_at`
  - If any check fails, the transaction rolls back and returns an error
- `task done <id>` must:
  - Set status to `done` and update `updated_at`
  - This may implicitly unblock other tasks (checked dynamically by `task next`)
- Dependency rules:
  - `task block <id> --by <blocker-id>` adds a row to the deps table
  - `task unblock <id> --by <blocker-id>` removes the row
  - Circular dependencies are not validated (agents are responsible for avoiding them)
  - A task with all blockers in `done` or `deleted` status is considered unblocked

## Constraints

- All scheduling queries must execute within a single SQLite transaction
- `task claim` must not succeed for two concurrent agents on the same task — SQLite's serialized writes guarantee this
- No task queue polling or wait mechanisms — agents call `task next` on demand

## Out of Scope

- Automatic task assignment or load balancing across agents
- Time-based scheduling (due dates, defer-until)
- Priority inheritance from blocking relationships
- Circular dependency detection or prevention
