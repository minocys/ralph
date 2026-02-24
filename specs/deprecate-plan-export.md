# Remove plan-export

Complete removal of the `ralph task plan-export` command, which was deprecated in favor of `ralph task list --all`.

## Overview

`ralph task plan-export` was deprecated after `ralph task list --all` was introduced as a functionally identical replacement. The deprecation phase added a stderr warning while keeping the command functional. This spec completes the removal by deleting the command entirely.

## Requirements

### Remove from task CLI

- Delete the `cmd_plan_export()` function from lib/task
- Remove the `plan-export)` case from the main dispatch in lib/task
- Remove any `plan-export` entry from the usage text (already removed in the deprecation phase)
- If `ralph task plan-export` is invoked, it must print an error to stderr: `Error: unknown command 'plan-export'. Use 'ralph task list --all' instead.` and exit 1

### Remove tests

- Delete `test/task_plan_export.bats` entirely
- Ensure `ralph task list --all` coverage exists in `test/task_list.bats` (the parity tests from the deprecation phase validated equivalence)

### Remove spec references

- Specs that previously referenced `plan-export` have already been updated to reference `list --all` during the deprecation phase
- Any remaining `plan-export` references in specs must be removed

## Constraints

- `ralph task plan-status` is not affected — it remains a separate command with distinct output (summary counts vs. task rows)
- `ralph task list --all` is the sole replacement — its behavior must match what `plan-export` provided
- `ralph task plan-sync` is not affected

## Out of Scope

- Changes to `ralph task list --all` behavior
- Changes to `ralph task plan-sync` input format
- Changes to `ralph task plan-status`
