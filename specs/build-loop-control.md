# Build Loop Control

Replace the text-based completion signal with task database status checks for ralph.sh iteration control.

## Requirements

- After each claude invocation in build mode, ralph.sh must run `task plan-status` to determine whether to continue the loop
- If `task plan-status` reports 0 open and 0 active tasks, ralph.sh must exit the loop successfully
- If tasks remain, ralph.sh must start the next iteration
- The `<promise>Tastes Like Burning.</promise>` grep check must be removed from the build loop in ralph.sh
- The `<promise>` completion signal must be retained in plan mode — the planner still uses it to signal completion
- The build skill prompt must not include a step for checking overall task completion — ralph.sh owns this decision

## Constraints

- `task plan-status` output format is defined in `specs/task-cli.md` — ralph.sh must parse it reliably
- The task CLI must be available and the database reachable for loop control to function — if `task plan-status` fails, ralph.sh should treat it as "tasks remain" and continue the loop
- This change only affects build mode (`--plan` mode retains the `<promise>` mechanism)

## Out of Scope

- Retry count thresholds (e.g., stopping after N failures on the same task)
- Switching between plan and build modes automatically
- Parallel agent coordination (each ralph.sh instance runs its own loop independently)
