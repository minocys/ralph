# Build Skill Integration

The ralph-build skill receives a task landscape snapshot via prompt input, selects the best task using LLM reasoning, claims it via targeted claiming, and implements it using atomic task CLI operations.

## Requirements

### Task Landscape Reception

- The builder receives a peek snapshot in markdown-KV format appended to its prompt by ralph.sh (see build-loop-control spec)
- Each task is a `## Task {id}` section with `key: value` lines (id, title, priority, status, category, spec, ref, assignee, deps, steps); null fields are omitted
- The snapshot contains two categories of tasks, distinguished by the `status` field:
  - `open` — claimable tasks sorted by priority, available for this agent to claim
  - `active` — tasks currently being worked on by other agents, with `assignee` indicating which agent
- The builder must read this markdown-KV to understand the current task landscape before selecting a task

### Task Selection

- The builder must use LLM reasoning to select which task to claim from the claimable tasks in the peek snapshot
- Selection should consider:
  - What other agents are currently working on (active tasks and their assignees) to avoid redundant work areas
  - Which task best advances the project given the current state of parallel work
  - Task priority as a baseline signal (lower number = higher priority), but the builder may deviate if it has good reason (e.g., complementing parallel work, avoiding conflicts)
- After selecting, the builder must claim the task via `task claim <id>` (targeted claiming — see task-scheduling spec)
- If `task claim <id>` exits with code 2 (task no longer eligible — claimed by another agent, blocked, etc.), the builder should select the next best task from the snapshot and retry; if no claimable tasks remain, stop gracefully
- After claiming, the builder must use commit SHAs from `blocker_results` in the claim output to review related upstream changes (e.g., `git show <sha>`) before implementing

### Implementation

- The builder must search the codebase before implementing — confirm before assuming missing
- The builder must mark individual steps complete via `task step-done <id> <seq>` as implementation progresses
- The builder must complete a task via `task done <id> --result '{"commit":"<sha>"}'` where `<sha>` is the commit SHA from the git commit just made
- The builder must release a task on failure via `task fail <id> --reason "<text>"` — this sets status back to `open`, clears the assignee, and increments `retry_count`
- The builder must use `task create` to log discovered bugs or new work items as tasks instead of editing a JSON file

### Boundaries

- The builder must not check overall completion status — loop control is handled by ralph.sh
- The builder must not start a new task after completing the claimed task — one task per session, unchanged
- The builder must still update @AGENTS.md with operational learnings
- The builder must still study `specs/*` during orientation

## Constraints

- The `result` JSON passed to `task done` must include a `commit` key — this is how downstream tasks receive context about upstream changes
- The agent's identity is available via `$RALPH_AGENT_ID` environment variable, set by ralph.sh before invoking Claude
- Status notes and progress belong in task steps and results, not in AGENTS.md
- Peek snapshot may be stale by the time the builder acts — targeted claiming with eligibility verification handles race conditions

## Out of Scope

- Lease renewal (`task renew`) — tasks should be small enough that 600 seconds suffices
- Retry count logic — ralph.sh does not react to retry_count
- Plan-phase operations (`task plan-sync`, `task plan-export`)
- Loop control decisions (covered by build-loop-control spec)
- Session crash recovery (covered by session-safety-hooks spec and build-loop-control crash-safety fallback)
