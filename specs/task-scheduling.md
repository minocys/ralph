# Task Scheduling

Lease-based claiming, DAG-aware scheduling, and idempotent plan synchronization for concurrent agents across multiple hosts.

## Requirements

### Claiming (Build Phase)

- `task claim` must return the highest-priority task that is:
  - Status is `open`, OR status is `active` with `lease_expires_at` in the past (expired lease)
  - Has no unresolved blockers (all tasks in its `blocked_by` set are `done` or `deleted`)
  - Not currently leased by another agent (enforced by `SELECT FOR UPDATE SKIP LOCKED`)
- Priority ordering: lower number = higher priority (0 before 1 before 2)
- Tiebreaker: `created_at` ascending (oldest first)
- The claim operation must be a single atomic transaction that:
  1. Selects the next eligible task with `FOR UPDATE SKIP LOCKED`
  2. Sets status to `active`, assignee to the agent ID, `lease_expires_at` to `now() + lease duration`
  3. If reclaiming from an expired lease, increments `retry_count`
  4. Updates `updated_at`
  5. Returns the full task row
  6. Fetches blocker results (result JSONB from all resolved blockers) within the same transaction
  - If no eligible task exists, returns exit code 2
- `task renew <id>` must extend `lease_expires_at` to `now() + lease duration` within a transaction that verifies the caller is the current assignee

### Lease-Based Recovery

- Tasks with `status = 'active'` and `lease_expires_at < now()` are considered abandoned
- Abandoned tasks are automatically eligible for re-claiming by `task claim` — no separate recovery command needed
- When an abandoned task is reclaimed, `retry_count` is incremented to track repeated failures
- Default lease duration is 600 seconds (10 minutes)

### Completion

- `task done <id>` must:
  - Verify the task status is `active`
  - Set status to `done`, store the result JSONB, update `updated_at`
  - This implicitly unblocks downstream tasks (checked dynamically by `task claim`)
- `task fail <id>` must:
  - Set status to `open`, clear assignee, clear `lease_expires_at`, increment `retry_count`, update `updated_at`
  - The task becomes eligible for re-claiming immediately

### Dependency Rules

- `task block <id> --by <blocker-id>` adds a row to the `task_deps` table
- `task unblock <id> --by <blocker-id>` removes the row
- Circular dependencies are not validated (the planner is responsible for avoiding them)
- A task with all blockers in `done` or `deleted` status is considered unblocked

### Plan Synchronization (Plan Phase)

- `task plan-sync` reads JSONL from stdin where each line represents a task with planner-assigned ID
- The diff algorithm operates per `spec_ref` group:
  - For each task in stdin:
    - If `id` exists in DB and task is `done` → skip (done tasks are immutable)
    - If `id` exists in DB and task is not `done` → update title, description, category, priority, steps, deps
    - If `id` does not exist → insert as new task with status `open`
  - For each task in DB whose `spec_ref` matches a spec_ref present in stdin, but whose `id` is NOT in stdin:
    - If task is `done` → leave it
    - Otherwise → soft delete (planner removed it from the plan)
- All operations within `plan-sync` must execute in a single transaction
- `plan-sync` must print a summary: `inserted: N, updated: N, deleted: N, skipped (done): N`

## Constraints

- All scheduling queries must execute within a single PostgreSQL transaction
- `task claim` must not succeed for two concurrent agents on the same task — `SELECT FOR UPDATE SKIP LOCKED` guarantees this
- No task queue polling or wait mechanisms — agents call `task claim` on demand
- Plan-sync must be idempotent — running it twice with the same input produces no changes on the second run

## Out of Scope

- Automatic task assignment or load balancing across agents
- Time-based scheduling (due dates, defer-until)
- Priority inheritance from blocking relationships
- Circular dependency detection or prevention
- Critical-path-aware scheduling (urgency scoring by downstream task count)
