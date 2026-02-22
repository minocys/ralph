# Build Loop Control

ralph.sh controls the build iteration lifecycle: pre-invocation task peek, invoking Claude with the task landscape, post-iteration status checks, and crash-safety fallback.

## Requirements

### Pre-invocation Task Peek

- Before each Claude invocation in build mode, ralph.sh must run `task peek -n 10` to get a snapshot of claimable and active tasks
- If `task peek` returns empty output (no claimable tasks), ralph.sh must exit the loop successfully — there is no work to do
- If `task peek` fails with a non-zero exit code, ralph.sh should treat it as a transient error and continue the loop (retry next iteration)
- ralph.sh must pass the peek output to Claude via the prompt argument: `claude -p "/ralph-build $PEEK_MD"`
- ralph.sh does not claim tasks — the build skill performs targeted claiming inside the session (see build-skill-integration spec)

### Post-invocation Checks

- After each Claude invocation completes, ralph.sh must check whether any task assigned to this agent is still `active` (not done or failed)
- If a task is still `active`, ralph.sh must run `task fail <id> --reason "session exited without completing task"` as a crash-safety fallback
- After the crash-safety check, ralph.sh must run `task plan-status` to determine whether to continue the loop
- If `task plan-status` reports 0 open and 0 active tasks, ralph.sh must exit the loop successfully
- If tasks remain, ralph.sh must start the next iteration

### Mode Separation

- The `<promise>Tastes Like Burning.</promise>` grep check must be removed from the build loop in ralph.sh
- The `<promise>` completion signal must be retained in plan mode — the planner still uses it to signal completion
- The build skill must not check overall task completion — ralph.sh owns loop control

## Constraints

- `task plan-status` output format is defined in `specs/task-cli.md` — ralph.sh must parse it reliably
- `task peek` output format is defined in `specs/task-cli.md` — ralph.sh passes it through without parsing (Claude parses it)
- If `task plan-status` fails (DB unreachable, CLI error), ralph.sh should treat it as "tasks remain" and continue the loop
- This change only affects build mode (`--plan` mode retains the `<promise>` mechanism)
- The crash-safety fallback is defense-in-depth — the SessionEnd hook (see session-safety-hooks spec) is the primary mechanism for releasing tasks on abnormal exits

## Out of Scope

- Retry count thresholds (e.g., stopping after N failures on the same task)
- Switching between plan and build modes automatically
- Parallel agent coordination (each ralph.sh instance runs its own loop independently)
- Parsing or interpreting the peek output in ralph.sh (it is passed through to Claude as-is)
