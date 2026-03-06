# Build Loop Control

`lib/build_loop.sh` controls the build iteration lifecycle: pre-invocation plan-status check, invoking Claude, post-iteration status checks, and crash-safety fallback.

## Requirements

### Pre-invocation Status Check

- Before each Claude invocation, the build loop must run `ralph task plan-status` to check whether work remains
- If `ralph task plan-status` reports 0 open and 0 active tasks, the loop must exit successfully — there is no work to do
- If tasks remain (or the check fails), proceed to invoke Claude
- The loop invokes Claude without pre-fetching task data: `claude -p "$COMMAND"` (plus flags for output format, model, etc.)
- The build skill loads its own task landscape via `!`command`` preprocessing in SKILL.md — the loop does not pass task data through the prompt

### Post-invocation Checks

- After each Claude invocation completes, the build loop must check whether any task assigned to this agent is still `active` (not done or failed)
- If a task is still `active`, the loop must run `ralph task fail <id> --reason "session exited without completing task"` as a crash-safety fallback
- After the crash-safety check, the loop must run `ralph task plan-status` to determine whether to continue — this is the same check as pre-invocation, reused
- If `ralph task plan-status` reports 0 open and 0 active tasks, the loop must exit successfully
- If tasks remain, the loop must start the next iteration

### Loop File

- Build loop logic lives in `lib/build_loop.sh`, sourced by `ralph build` (see cli-subcommand-dispatch spec)
- `setup_session()` is shared between plan and build modes
- The build skill must not check overall task completion — the build loop owns loop control

## Constraints

- `ralph task plan-status` output format is defined in `specs/task-cli.md` — the build loop must parse it reliably
- If `ralph task plan-status` fails (DB unreachable, CLI error), the loop should treat it as "tasks remain" and continue
- The crash-safety fallback is defense-in-depth — the SessionEnd hook (see session-safety-hooks spec) is the primary mechanism for releasing tasks on abnormal exits

## Out of Scope

- Retry count thresholds (e.g., stopping after N failures on the same task)
- Switching between plan and build modes automatically
- Parallel agent coordination (each ralph.sh instance runs its own loop independently)
