# Task CLI Relocation

Move the standalone `task` script from the project root into `lib/task` and route user access through `ralph task <cmd>`.

## Requirements

### File relocation

- Move `./task` to `./lib/task` (no `.sh` extension, preserving the current naming convention)
- The script must remain executable (`chmod +x`)
- The script's internal symlink resolution must be updated to locate `.env` and other files relative to the new location (one directory deeper in lib/)

### User-facing invocation

- Users and skills invoke task commands via `ralph task <cmd> [args]` (e.g., `ralph task peek -n 10`)
- `ralph.sh` routes the `task` subcommand by exec'ing to `lib/task` with remaining arguments (see cli-subcommand-dispatch spec)

### Skill updates

- `ralph-build/SKILL.md` must change all `task <cmd>` references to `ralph task <cmd>`:
  - `ralph task claim <id>`
  - `ralph task done <id> --result '...'`
  - `ralph task fail <id> --reason "..."`
  - `ralph task create <id> <title> ...`
- `ralph-plan/SKILL.md` must change `task plan-sync` to `ralph task plan-sync`

### Hook behavior

- Hooks (`hooks/precompact.sh`, `hooks/session_end.sh`) must continue using `$RALPH_TASK_SCRIPT`
- `$RALPH_TASK_SCRIPT` must point to `$SCRIPT_DIR/lib/task` (updated path)
- No changes to hook logic beyond the updated path

### Internal callers

- `lib/plan_loop.sh` and `lib/build_loop.sh` must reference the task script via `$TASK_SCRIPT` variable, set to `"$SCRIPT_DIR/lib/task"`
- `lib/signals.sh` must continue using `$TASK_SCRIPT` for agent deregistration
- `$RALPH_TASK_SCRIPT` must be exported for hooks and Claude sessions

### Install script

- `install.sh` must remove the `~/.local/bin/task` symlink creation
- Only `~/.local/bin/ralph` symlink remains
- If an existing `~/.local/bin/task` symlink exists from a previous install, `install.sh` should remove it with an informational message

### Task script self-references

- The `usage()` function in lib/task must update from `Usage: task <command>` to `Usage: ralph task <command>`
- Error messages referencing `task` as a command must be updated to `ralph task`

## Constraints

- The task script's internal functionality (all subcommands, SQL, schema) must not change
- `$RALPH_TASK_SCRIPT` must always resolve to an absolute path to lib/task
- Hooks must not depend on `ralph` being on PATH — they use the env var for robustness

## Out of Scope

- Changing task CLI subcommands or their behavior
- Merging task functionality into ralph.sh
- Adding task subcommands to the top-level ralph CLI (no `ralph peek` shortcuts)
