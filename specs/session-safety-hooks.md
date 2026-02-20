# Session Safety Hooks

Claude Code hooks that ensure active tasks are properly released when agent sessions end, whether from context limits or unexpected exits.

## Requirements

### PreCompact Hook

- When the PreCompact event fires, the hook must:
  1. Determine the currently active task for this agent by querying `task list --status active --json` and filtering by `$RALPH_AGENT_ID`
  2. Log a warning to stderr identifying the agent and task
  3. Run `task fail <id> --reason "context limit reached"` to release the task for retry
  4. Output `{ "continue": false, "stopReason": "Context Limit Reached" }` to stdout
  5. Exit with code 0
- This causes the claude CLI to stop, and ralph.sh begins the next iteration with `retry_count` incremented on the failed task

### SessionEnd Hook

- When the SessionEnd event fires, the hook must:
  1. Determine the currently active task for this agent by querying `task list --status active --json` and filtering by `$RALPH_AGENT_ID`
  2. If an active task exists, log a warning to stderr identifying the agent and task
  3. Run `task fail <id> --reason "session ended unexpectedly"` to release the task for retry
  4. Exit with code 0
- This catches cases where the agent exits without properly calling `task done` or `task fail` (crashes, timeouts, user interrupts)

### Interaction with ralph.sh

- ralph.sh's existing `cleanup()` EXIT trap handles agent deregistration (`task agent deregister`)
- ralph.sh also has a crash-safety fallback that fails tasks still `active` after Claude exits (see build-loop-control spec)
- Defense-in-depth: hooks are the primary mechanism (fire inside the session), ralph.sh's fallback is secondary (fires after the session exits)
- Order: SessionEnd hook fails the task → ralph.sh crash-safety check (no-op if hook succeeded) → ralph.sh EXIT trap deregisters the agent

## Constraints

- Hooks must be configured in `.claude/settings.json` (or `.claude/settings.local.json`) under the `hooks` key
- Hooks must be idempotent — if the task was already completed or failed, `task fail` should handle this gracefully
- The `$RALPH_AGENT_ID` environment variable must be available to hooks (exported by ralph.sh)
- The `task` script path must be discoverable by hooks (via `$RALPH_TASK_SCRIPT` or a known relative path)
- Hooks must not block indefinitely — database unavailability should not hang the hook (use timeouts or `|| true`)

## Out of Scope

- Hooks for plan mode — the planner does not claim tasks, so there is nothing to fail
- Automatic task decomposition when retry_count exceeds a threshold
- Notification or alerting when tasks are failed by hooks
