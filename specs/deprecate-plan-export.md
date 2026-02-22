# Deprecate plan-export

Consolidate `task plan-export` into `task list --all` to eliminate a redundant command. The two commands produce identical output — the only difference is that `plan-export` includes deleted tasks while `list` excludes them by default.

## Requirements

### Add `--all` flag to `task list`

- `task list --all` must remove the status filter entirely — return all tasks including deleted, matching the current `plan-export` behavior
- `--all` and `--status` are mutually exclusive — if both are provided, print an error to stderr and exit 1
- `--all` must work with `--markdown` — `task list --all --markdown` replaces `task plan-export --markdown`
- Sort order is unchanged: `priority ASC, created_at ASC`

### Deprecate `task plan-export`

- `task plan-export` must remain functional — do not remove the command
- On every invocation, `plan-export` must print a deprecation warning to stderr: `Warning: plan-export is deprecated, use 'task list --all [--markdown]' instead`
- The deprecation warning must not interfere with stdout output — callers that capture stdout continue to work
- The main dispatch must continue to route `plan-export` to `cmd_plan_export`

### Migrate callers

- `lib/loop.sh`: change `plan-export --markdown` to `list --all --markdown`
- `task` script usage text: remove `plan-export` from the Plan Phase Commands section, add `--all` to the `list` entry under Shared Commands
- Test files: `test/task_plan_export.bats` must be updated to exercise `task list --all` and verify the deprecation warning on `plan-export`

### Update specs

- `specs/task-cli.md`: remove `plan-export` from Plan Phase Commands, update `list` to document `--all`, update the table format section to reference `list` only
- `specs/task-output-format.md`: replace the `plan-export` section with `list --all`, update the title/overview to reference `list --all` instead of `plan-export`, update the Loop Integration section
- `specs/plan-skill-integration.md`: change `task plan-export --markdown` to `task list --all --markdown` in all requirements
- `specs/build-skill-integration.md`: update the Out of Scope reference from `task plan-export` to `task list --all`
- `specs/scoped-task-lists.md`: replace `task plan-export` with `task list --all` in the CLI Behavior requirements
- `specs/task-steps-simplification.md`: replace the "Update plan-export" section with "Update list --all" referencing `task list --all`
- `specs/README.md`: update the `task-output-format.md` description to reference `list --all` instead of `plan-export`

## Constraints

- `task plan-status` is not affected — it remains a separate command with distinct output (summary counts vs. task rows)
- The deprecation is stderr-only — stdout output of `plan-export` must remain byte-identical to the equivalent `list --all` invocation
- `cmd_plan_export` implementation can be simplified to delegate to `cmd_list` internally (with `--all` injected), but this is an implementation choice, not a requirement

## Out of Scope

- Removing `plan-export` entirely (it stays as a deprecated alias)
- Changes to `plan-sync` input format or behavior
- Changes to `plan-status`
- Adding `--all` semantics to `peek` or other commands
- Scope filtering changes (covered by `scoped-task-lists.md`)
