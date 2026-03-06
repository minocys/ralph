# Plan Loop Control

Replace the sentinel-based while-true loop with a deterministic for-loop for plan mode.

## Overview

The current plan-mode loop runs `while true` and exits when it detects `<promise>Tastes Like Burning.</promise>` in the last assistant message via jq+grep. This mechanism is fragile — if the sentinel appears in a non-terminal message (e.g., a subagent response followed by additional output), the loop misses it and continues indefinitely. A for-loop eliminates this fragility by running a fixed number of iterations.

## Requirements

### For-loop iteration

- Plan mode must use a `for` loop that iterates exactly N times (default N=1)
- The `--max-iterations` / `-n` flag controls N
- When `-n` is not provided in plan mode, N defaults to 1 (one-shot planning)
- `-n 0` must be rejected in plan mode with an error message — plan mode requires a positive iteration count
- Build mode is unaffected — it retains the while-true loop with `-n 0` meaning unlimited

### Sentinel removal

- Remove the `<promise>Tastes Like Burning.</promise>` sentinel check from the loop entirely
- Remove the jq+grep check that scans $TMPFILE for the sentinel
- Remove step 4 from `ralph-plan/SKILL.md` ("When complete, reply with: `<promise>Tastes Like Burning.</promise>`")
- The planner no longer emits any completion signal — it does its work and the loop handles exit

### Pre-invocation data fetch

- The plan loop passes `$COMMAND` to Claude without pre-fetching task data — the plan skill loads its own task DAG via `` !`command` `` preprocessing in SKILL.md
- The loop invocation is simply: `claude -p "$COMMAND"` (plus flags for output format, model, etc.)

### Post-invocation behavior

- No post-invocation checks in plan mode — the for-loop proceeds to the next iteration or exits
- No crash-safety fallback needed in plan mode — the planner does not claim tasks

### Loop file

- Plan loop logic lives in `lib/plan_loop.sh` (see cli-subcommand-dispatch spec for module sourcing)
- `setup_session()` is shared between plan and build modes (provides scope derivation, temp file creation)

## Constraints

- Build mode loop control is unchanged (covered by build-loop-control spec)
- The plan skill's behavior (studying specs, emitting JSONL to plan-sync) is unchanged — only the exit mechanism changes
- `-n` flag semantics differ between modes: plan requires >= 1, build allows 0 (unlimited)

## Out of Scope

- Changing how the plan skill studies specs or generates tasks
- Adding early-exit detection (e.g., "no changes needed" check between iterations)
- Automatic iteration count selection based on project size
- Build loop changes (covered by build-loop-control spec)
