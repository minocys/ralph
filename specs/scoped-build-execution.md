# Scoped Build Execution

When `ralph build --specs <patterns>` is invoked, the build loop only presents matching tasks to the builder and exits when all matching tasks are complete.

## Requirements

### Build loop behavior

- When `SPEC_FILTER` is non-empty, the build loop exports `RALPH_SPEC_FILTER` as an environment variable and passes `--specs "$SPEC_FILTER"` to `ralph task plan-status` (direct bash invocation)
- The dynamic context injection in the build skill's SKILL.md is always `` !`ralph task peek -n 10` `` — the peek command reads `RALPH_SPEC_FILTER` from the environment internally, so no bash parameter expansion is needed in the skill template
- When `SPEC_FILTER` is empty, `RALPH_SPEC_FILTER` is unset, and peek returns all tasks (unchanged behavior)
- SKILL.md must not use `${RALPH_SPEC_FILTER:+...}` or any bash variable expansion — Claude Code's backtick preprocessor does not support shell variable expansion syntax

### Pre-invocation status check

- `ralph task plan-status --specs "$SPEC_FILTER"` reports counts of open and active tasks matching the filter
- If 0 open and 0 active matching tasks, the loop exits successfully — the targeted work is complete
- Unmatched tasks (belonging to other specs) are ignored for exit determination

### Builder task selection

- The builder only sees tasks matching the `--specs` filter in its peek snapshot
- The builder's task selection reasoning operates on this filtered set — it cannot claim tasks outside the filter
- If the builder attempts a targeted claim on a task outside the filter (should not happen since peek is filtered), the claim proceeds normally at the `ralph task claim` level — filtering is advisory at the peek/plan-status layer, not enforced at the claim layer

### Post-invocation crash-safety

- The crash-safety fallback (failing tasks still `active` for this agent) is unchanged — it operates on the agent's active tasks regardless of the `--specs` filter
- An agent that claimed a matching task must still have it failed on crash, even if `--specs` changes between iterations (which it won't, since it's fixed for the loop's lifetime)

### Interaction with unfiltered builds

- An unfiltered `ralph build` sees all tasks as before
- Running `ralph build --specs ui-tabs` in one terminal and `ralph build --specs auth*` in another is safe — each loop only presents its filtered tasks, and `ralph task claim` prevents double-claiming via `BEGIN IMMEDIATE` transactions
- Running `ralph build --specs ui-tabs` alongside an unfiltered `ralph build` is also safe — the unfiltered builder may claim `ui-tabs` tasks too, since claim-level filtering is not enforced

## Constraints

- The `--specs` filter is fixed for the lifetime of a build loop invocation — it does not change between iterations
- `RALPH_SPEC_FILTER` must be available in the Claude process environment so the task CLI can read it as a fallback for `--specs`
- The task CLI commands (`peek`, `plan-status`) handle both filtered and unfiltered cases transparently based on the environment variable

## Out of Scope

- Claim-level enforcement of the spec filter (filtering is at the peek/plan-status layer only)
- Dynamic filter changes during a build loop
- Automatic spec filter inference from git diff or changed files
- Load balancing across filtered build instances
