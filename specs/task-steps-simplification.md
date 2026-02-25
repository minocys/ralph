# Task Steps Simplification

Replace the `task_steps` table with a `TEXT[]` column on the `tasks` table and remove per-step status tracking.

## Requirements

### Schema Change

- Add a `steps TEXT[]` column to the `tasks` table (nullable, default NULL)
- Each array element is a plain string step description (no sequence number, no status)
- Drop the `task_steps` table entirely (not a migration — rebuild schema from scratch per existing convention)
- The `ensure_schema` function must create the `tasks` table with the new `steps` column and must not create `task_steps`

### Remove step-done Command

- Remove the `step-done` subcommand from the task CLI (`lib/task`)
- Remove `cmd_step_done()` function
- Remove `step-done` from the main dispatch, usage text, and help output

### Update plan-sync

- Steps in JSONL input change from `[{"content":"..."}]` to `["step1","step2"]` (plain string array)
- `plan-sync` must write steps as a PostgreSQL TEXT[] literal (e.g., `ARRAY['step1','step2']`) instead of inserting into `task_steps`
- On update, `plan-sync` must overwrite the `steps` column directly

### Update create

- The `-s STEPS_JSON` flag on `ralph task create` must accept a JSON array of strings (e.g., `'["step1","step2"]'`) instead of `[{"content":"..."}]`
- Write steps directly to the `steps` column as a TEXT[] value

### Update update

- The `--steps` flag on `ralph task update` must accept a JSON array of strings
- Write steps directly to the `steps` column as a TEXT[] value

### Update show

- `ralph task show` must render steps from the `steps` column as a numbered list
- No status indicator per step (was `[pending]`/`[done]` — now just the step text)

### Update claim

- `ralph task claim` must read steps from the `steps` column instead of joining `task_steps`
- Steps in output are a plain list (no seq/status metadata)

### Update list --all

- `ralph task list --all` (and `ralph task list --all --markdown`) must read steps from the `steps` column instead of joining `task_steps`

### Update list

- `ralph task list --markdown` must read steps from the `steps` column instead of joining `task_steps`

### Update peek

- `ralph task peek` does not currently include steps — no change needed unless steps are added to peek output

### Skill Prompts

- Remove `ralph task step-done <id> <seq>` from `ralph-build` SKILL.md (step 6)
- The builder no longer tracks individual step progress — steps are informational only

## Constraints

- No database migration system — `ensure_schema` uses `CREATE TABLE IF NOT EXISTS`, so the schema change requires a fresh database or manual `ALTER TABLE`
- Steps are informational only after this change — they guide the builder but are not tracked for completion
- The `steps` column stores a Postgres `TEXT[]` array, not JSONB
- Existing data in `task_steps` will be lost when the table is dropped (acceptable — tasks are ephemeral per planning cycle)

## Out of Scope

- Adding step completion tracking back in a different form
- Changing how the planner generates steps (it still emits them in plan-sync JSONL)
- Migrating existing step data from `task_steps` to the new column
