# Plan Skill Integration

The plan skill loads its own task DAG via `` !`ralph task list --all --markdown` `` preprocessing syntax in SKILL.md. The plan skill writes task state via `ralph task plan-sync`.

## Requirements

### Task State Reception

- The skill must use `` !`ralph task list --all --markdown` `` in its SKILL.md to load the current task DAG at skill expansion time (Claude Code's dynamic context injection — the command output replaces the placeholder before Claude sees the prompt)
- If the command returns empty output (no tasks yet), the skill treats the empty section as a fresh start
- The plan loop (`lib/plan_loop.sh`) passes `$COMMAND` without pre-fetching data — the skill owns its data loading

### Task State Writing

- The planner must write task state by emitting JSONL to stdin of `ralph task plan-sync`
- The planner must assign stable task IDs in `{spec-slug}/{seq}` format (e.g., `task-cli/01`) where `spec-slug` matches the spec filename without the `.md` extension
- The planner must set `spec_ref` on every task to the source spec filename (e.g., `task-cli.md`)
- The planner must express dependencies between tasks using `deps` when task B requires task A's output
- The planner must set priority as an integer: 0=critical, 1=high, 2=medium, 3=low
- The JSONL format and field names are defined in `specs/task-cli.md` — the skill prompt must reference that spec rather than embedding format examples

### Skill Prompt

- The skill prompt must not reference IMPLEMENTATION_PLAN.json in any step
- The skill prompt must not call `ralph task plan-status` — it is not needed for planning
- The planner must still author new spec files at `specs/FILENAME.md` when elements are missing, using short kebab-case filenames since these become `spec_ref` values and task ID prefixes
- The planner does not emit any completion signal — the plan loop uses a deterministic for-loop to control iterations (see plan-loop-control spec)

## Constraints

- Spec filenames must be short, kebab-case slugs — they are used as `spec_ref` in the task system and form the first segment of task IDs
- The planner must not implement anything — plan-only constraint is unchanged
- `ralph task plan-sync` semantics: done tasks are immutable (skipped), tasks removed from stdin are soft-deleted, tasks present in both are updated
- The planner still uses subagents for research and analysis — only the persistence layer changes
- The task DAG snapshot may be stale by the time the planner acts — this is acceptable since only one planner runs at a time

## Out of Scope

- Changes to how the planner studies specs or searches the codebase (steps 0a, 0c are unchanged)
- Task CLI implementation (covered by `specs/task-cli.md`)
- Database schema (covered by `specs/task-data-store.md`)
- Build-phase task operations (covered by build skill integration spec)
- Input validation for `ralph task plan-sync` (covered by `specs/plan-sync-validation.md`)
