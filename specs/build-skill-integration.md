# Build Skill Integration

Migrate ralph-build from IMPLEMENTATION_PLAN.json to atomic task CLI operations for claiming, executing, and completing tasks.

## Requirements

- The builder must run `task plan-status` during orientation (step 0b) instead of reading IMPLEMENTATION_PLAN.json
- The builder must run `task claim` to atomically claim the next highest-priority unblocked task instead of manually picking from a JSON file
- The builder must parse the JSON output of `task claim`, which includes task fields, steps, and `blocker_results` (a map of blocker task IDs to their result JSONB, including commit SHAs)
- The builder must use commit SHAs from `blocker_results` to review related upstream changes (e.g., `git show <sha>`) before implementing
- The builder must mark individual steps complete via `task step-done <id> <seq>` as implementation progresses
- The builder must complete a task via `task done <id> --result '{"commit":"<sha>"}'` where `<sha>` is the commit SHA from the git commit just made
- The builder must release a task on failure via `task fail <id> --reason "<text>"` — this sets status back to `open`, clears the assignee, and increments `retry_count`
- The builder must use `task create` to log discovered bugs or new work items as tasks instead of editing a JSON file
- The builder must not reference IMPLEMENTATION_PLAN.json in any step
- The builder must not check overall completion status — loop control is handled by ralph.sh (see build loop control spec)
- The builder must not start a new task after completing the claimed task — one task per session, unchanged
- The builder must still update @AGENTS.md with operational learnings
- The builder must still study `specs/*` during orientation

## Constraints

- `task claim` returns exit code 2 when no eligible tasks exist — the builder should stop gracefully in this case
- The `result` JSON passed to `task done` must include a `commit` key — this is how downstream tasks receive context about upstream changes
- The agent's identity is available via `$RALPH_AGENT_ID` environment variable, set by ralph.sh before invoking claude
- Lease duration is 600 seconds — tasks are expected to be small enough to complete within this window without renewal
- Status notes and progress belong in task steps and results, not in AGENTS.md

## Out of Scope

- Lease renewal (`task renew`) — tasks should be small enough that 600 seconds suffices
- Retry count logic — ralph.sh does not react to retry_count
- Plan-phase operations (`task plan-sync`, `task plan-export`)
- Loop control decisions (covered by build loop control spec)
- Session crash recovery (covered by session safety hooks spec)
