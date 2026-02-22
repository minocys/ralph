# Plan Skill Integration

Migrate ralph-plan from IMPLEMENTATION_PLAN.json to the PostgreSQL-backed task CLI for reading and writing task state. The outer loop pre-fetches the task DAG and passes it to the plan skill as an argument.

## Requirements

### Task State Reception

- ralph.sh must run `task list --all --markdown` before each plan-mode Claude invocation and capture the output
- ralph.sh must pass the captured markdown-KV to Claude via the prompt argument: `claude -p "/ralph-plan $LIST_ALL_MD"` (mirrors the build-mode peek pattern in `specs/build-loop-control.md`)
- If `task list --all --markdown` returns empty output (no tasks yet), ralph.sh must still pass the empty string — the skill treats empty input as a fresh start
- The skill must declare `argument-hint: [current-task-dag]` in its SKILL.md front-matter
- The skill must reference the provided task DAG snapshot in its instructions rather than calling `task list --all` directly

### Task State Writing

- The planner must write task state by emitting JSONL to stdin of `task plan-sync`
- The planner must assign stable task IDs in `{spec-slug}/{seq}` format (e.g., `task-cli/01`) where `spec-slug` matches the spec filename without the `.md` extension
- The planner must set `spec_ref` on every task to the source spec filename (e.g., `task-cli.md`)
- The planner must express dependencies between tasks using `deps` when task B requires task A's output
- The planner must set priority as an integer: 0=critical, 1=high, 2=medium, 3=low
- The JSONL format and field names are defined in `specs/task-cli.md` — the skill prompt must reference that spec rather than embedding format examples

### Skill Prompt

- The skill prompt must not reference IMPLEMENTATION_PLAN.json in any step
- The skill prompt must not call `task list --all` — the data is provided as input
- The skill prompt must not call `task plan-status` — it is not needed for planning
- The planner must still author new spec files at `specs/FILENAME.md` when elements are missing, using short kebab-case filenames since these become `spec_ref` values and task ID prefixes
- The `<promise>Tastes Like Burning.</promise>` completion signal must be retained for the planner (loop control changes only apply to the build loop)

## Constraints

- Spec filenames must be short, kebab-case slugs — they are used as `spec_ref` in the task system and form the first segment of task IDs
- The planner must not implement anything — plan-only constraint is unchanged
- `task plan-sync` semantics: done tasks are immutable (skipped), tasks removed from stdin are soft-deleted, tasks present in both are updated
- The planner still uses subagents for research and analysis — only the persistence layer changes
- The task DAG snapshot may be stale by the time the planner acts — this is acceptable since only one planner runs at a time

## Out of Scope

- Changes to how the planner studies specs or searches the codebase (steps 0a, 0c are unchanged)
- Task CLI implementation (covered by `specs/task-cli.md`)
- Database schema (covered by `specs/task-data-store.md`)
- Build-phase task operations (covered by build skill integration spec)
- Input validation for `task plan-sync` (covered by `specs/plan-sync-validation.md`)
