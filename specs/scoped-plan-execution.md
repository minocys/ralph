# Scoped Plan Execution

When `ralph plan --specs <patterns>` is invoked, the planner reads all specs for full context but only emits tasks for the targeted spec_refs, and `plan-sync` limits orphan deletion to the targeted scope.

## Requirements

### Plan loop behavior

- When `SPEC_FILTER` is non-empty, the plan loop exports `RALPH_SPEC_FILTER` as an environment variable — `plan-sync` reads it from the environment as a fallback when `--specs` is not passed explicitly
- The plan loop does not filter which specs the planner reads — the `COMMAND` variable remains `/ralph-plan` unchanged
- The plan skill's dynamic context injection (`` !`ralph task list --all --markdown` ``) is also unchanged — the planner sees the full task DAG for dependency awareness

### Planner skill behavior

- The planner always reads all files in `specs/*` regardless of `--specs` — this preserves cross-spec context for dependency planning
- After gap analysis, the planner emits JSONL only for tasks whose `spec_ref` matches the `--specs` patterns
- The planner must not emit tasks for unmatched specs, even if gaps are found — those are left for a future unfiltered run
- If the planner creates a new spec file during execution, and the new spec's slug matches a `--specs` pattern, it may emit tasks for that new spec
- The plan skill's SKILL.md references `ralph task plan-sync` without any bash variable expansion — the `plan-sync` command reads `RALPH_SPEC_FILTER` from the environment automatically, so the skill prompt uses the plain command name

### plan-sync scoped orphan deletion

- `plan-sync` resolves its spec patterns from either the `--specs` flag or the `RALPH_SPEC_FILTER` environment variable (flag takes precedence)
- Orphan deletion candidates are restricted to tasks whose `spec_ref` matches at least one pattern AND whose `spec_ref` appears in the input JSONL
- Tasks whose `spec_ref` does not match any pattern are immune to orphan deletion
- This is the critical safety mechanism: a targeted plan run must not destroy tasks outside its scope

### Interaction with unfiltered runs

- An unfiltered `ralph plan` (no `--specs`) continues to operate on all spec_refs as before
- Running `ralph plan --specs ui-tabs` followed by `ralph plan` (unfiltered) is safe — the unfiltered run will process all spec_refs including `ui-tabs`
- The `--specs` filter has no persistent state — it only affects the current invocation

## Constraints

- The planner is an LLM — the instruction to only emit tasks for matched specs is a prompt-level directive, not an enforced filter
- `plan-sync --specs` is the enforcement layer: even if the planner emits tasks for unmatched specs, the orphan deletion scope is still limited to matched patterns
- Insert and update operations from `plan-sync` are not blocked by `--specs` — if the planner emits a task for an unmatched spec, it will still be inserted/updated (only orphan deletion is scoped)

## Out of Scope

- Filtering which spec files the planner reads (it always reads all specs)
- Filtering the task DAG injected via `ralph task list --all --markdown`
- Persistent spec filter configuration across plan runs
- Automatically determining which specs need re-planning based on code changes
