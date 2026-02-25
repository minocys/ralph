# Task Scheduling

Lease-based claiming, DAG-aware scheduling, and idempotent plan synchronization for concurrent agents across multiple hosts.

## Requirements

### Peek (Build Phase)

- `ralph task peek [-n N]` returns a read-only snapshot of the task landscape for agent decision-making
- Claimable tasks: the top N tasks matching claim eligibility criteria (see below), sorted by priority ASC then `created_at` ASC
- Active tasks: all tasks with `status = 'active'` regardless of N limit, including their `assignee` field
- Output is markdown-KV format (each task as a `## Task {id}` section with `key: value` lines), with claimable and active tasks distinguished by the `status` field — `open` for claimable, `active` for in-progress
- Peek is non-locking — it does not acquire `FOR UPDATE` locks, so the snapshot may be stale by the time the agent acts on it
- If no claimable or active tasks exist, output is empty and exit code is 0

### Claiming (Build Phase)

- A task is eligible for claiming if it:
  - Has status `open`, OR has status `active` with `lease_expires_at` in the past (expired lease)
  - Has no unresolved blockers (all tasks in its `blocked_by` set are `done` or `deleted`)
  - Is not currently leased by another agent (enforced by `SELECT FOR UPDATE SKIP LOCKED`)
- Priority ordering: lower number = higher priority (0 before 1 before 2)
- Tiebreaker: `created_at` ascending (oldest first)

#### Untargeted Claim

- `ralph task claim` (no ID argument) selects the highest-priority eligible task automatically
- The claim operation must be a single atomic transaction that:
  1. Selects the next eligible task with `FOR UPDATE SKIP LOCKED`
  2. Sets status to `active`, assignee to the agent ID, `lease_expires_at` to `now() + lease duration`
  3. If reclaiming from an expired lease, increments `retry_count`
  4. Updates `updated_at`
  5. Returns the full task row
  6. Fetches blocker results (result JSONB from all resolved blockers) within the same transaction
  - If no eligible task exists, returns exit code 2

#### Targeted Claim

- `ralph task claim <id>` claims a specific task chosen by the agent after reviewing the peek snapshot
- The claim must verify eligibility before proceeding — the task must meet the same criteria as untargeted claim (open + unblocked, or active with expired lease)
- If the specified task is not eligible (already claimed by another agent, blocked, done, or deleted), return exit code 2
- The claim operation uses the same atomic transaction pattern as untargeted claim, but targets the specified task ID instead of selecting by priority
- Targeted claiming enables LLM-driven task selection: the agent reviews the peek landscape, reasons about what complements parallel work, and claims the best task

### Lease Renewal

- `ralph task renew <id>` must extend `lease_expires_at` to `now() + lease duration` within a transaction that verifies the caller is the current assignee

### Lease-Based Recovery

- Tasks with `status = 'active'` and `lease_expires_at < now()` are considered abandoned
- Abandoned tasks are automatically eligible for re-claiming by `ralph task claim` — no separate recovery command needed
- When an abandoned task is reclaimed, `retry_count` is incremented to track repeated failures
- Default lease duration is 600 seconds (10 minutes)

### Completion

- `ralph task done <id>` must:
  - Verify the task status is `active`
  - Set status to `done`, store the result JSONB, update `updated_at`
  - This implicitly unblocks downstream tasks (checked dynamically by `ralph task claim`)
- `ralph task fail <id>` must:
  - Set status to `open`, clear assignee, clear `lease_expires_at`, increment `retry_count`, update `updated_at`
  - The task becomes eligible for re-claiming immediately

### Dependency Rules

- `ralph task block <id> --by <blocker-id>` adds a row to the `task_deps` table
- `ralph task unblock <id> --by <blocker-id>` removes the row
- Circular dependencies are not validated (the planner is responsible for avoiding them)
- A task with all blockers in `done` or `deleted` status is considered unblocked

### Plan Synchronization (Plan Phase)

- `ralph task plan-sync` reads JSONL from stdin where each line represents a task with planner-assigned ID
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
- `ralph task claim` must not succeed for two concurrent agents on the same task — `SELECT FOR UPDATE SKIP LOCKED` guarantees this
- No task queue polling or wait mechanisms — agents call `ralph task claim` on demand
- Plan-sync must be idempotent — running it twice with the same input produces no changes on the second run

## Out of Scope

- Automatic task assignment or load balancing across agents
- Time-based scheduling (due dates, defer-until)
- Priority inheritance from blocking relationships
- Circular dependency detection or prevention
- Critical-path-aware scheduling (urgency scoring by downstream task count)
