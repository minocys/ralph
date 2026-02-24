# Build Loop Control

`lib/build_loop.sh` controls the build iteration lifecycle: pre-invocation task peek, invoking Claude with the task landscape, post-iteration status checks, and crash-safety fallback.

## Requirements

### Pre-invocation Task Peek

- Before each Claude invocation, the build loop must run `ralph task peek -n 10` to get a snapshot of claimable and active tasks
- If `ralph task peek` returns empty output (no claimable tasks), the loop must exit successfully — there is no work to do
- If `ralph task peek` fails with a non-zero exit code, the loop should treat it as a transient error and continue (retry next iteration)
- The loop must pass the peek output to Claude via the prompt argument: `claude -p "/ralph-build $PEEK_MD"`
- The loop does not claim tasks — the build skill performs targeted claiming inside the session (see build-skill-integration spec)

### Post-invocation Checks

- After each Claude invocation completes, the build loop must check whether any task assigned to this agent is still `active` (not done or failed)
- If a task is still `active`, the loop must run `ralph task fail <id> --reason "session exited without completing task"` as a crash-safety fallback
- After the crash-safety check, the loop must run `ralph task plan-status` to determine whether to continue
- If `ralph task plan-status` reports 0 open and 0 active tasks, the loop must exit successfully
- If tasks remain, the loop must start the next iteration

### Loop File

- Build loop logic lives in `lib/build_loop.sh`, sourced by `ralph build` (see cli-subcommand-dispatch spec)
- `setup_session()` is shared between plan and build modes
- The build skill must not check overall task completion — the build loop owns loop control

## Constraints

- `ralph task plan-status` output format is defined in `specs/task-cli.md` — the build loop must parse it reliably
- `ralph task peek` output format is defined in `specs/task-cli.md` — the loop passes it through without parsing (Claude parses it)
- If `ralph task plan-status` fails (DB unreachable, CLI error), the loop should treat it as "tasks remain" and continue
- The crash-safety fallback is defense-in-depth — the SessionEnd hook (see session-safety-hooks spec) is the primary mechanism for releasing tasks on abnormal exits

## Out of Scope

- Retry count thresholds (e.g., stopping after N failures on the same task)
- Switching between plan and build modes automatically
- Parallel agent coordination (each ralph.sh instance runs its own loop independently)
- Parsing or interpreting the peek output in ralph.sh (it is passed through to Claude as-is)
