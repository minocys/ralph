# Spec Filter Flag

A `--specs` flag for `ralph plan` and `ralph build` that accepts comma-separated glob patterns matched against spec-slugs, enabling targeted execution on a subset of specs.

## Requirements

### Flag definition

- `ralph plan` and `ralph build` accept `--specs <patterns>` as an optional flag
- The value is a comma-separated list of glob patterns (e.g., `--specs 'ui-tabs,auth*'`)
- Each pattern is matched against the spec-slug portion of task IDs (the part before the `/` in `{spec-slug}/{seq}`)
- Shell-style glob matching: `*` matches any sequence of characters, `?` matches a single character (standard `bash` `[[ $slug == $pattern ]]` case-matching semantics)
- When `--specs` is omitted, behavior is unchanged — all specs are in scope
- `parse_flags` in `lib/config.sh` stores the raw value in a global `SPEC_FILTER` variable (empty string when not provided)

### Pattern validation

- An empty `--specs ''` (flag present but empty value) must be rejected with an error to stderr and exit 1
- Patterns are not validated against existing spec filenames — invalid patterns simply match nothing
- Whitespace around commas is not trimmed — patterns are split strictly on `,`

### Propagation

- The plan and build loops export `RALPH_SPEC_FILTER` as an environment variable when `SPEC_FILTER` is non-empty; unset it otherwise
- The task CLI subcommands (`peek`, `plan-status`, `plan-sync`) read `RALPH_SPEC_FILTER` from the environment as a fallback when `--specs` is not passed on the command line — an explicit `--specs` flag always takes precedence over the environment variable
- The build loop passes `SPEC_FILTER` to `ralph task plan-status` via `--specs "$SPEC_FILTER"` when non-empty (direct bash invocation, not via skill)
- The `COMMAND` variable (the skill prompt) is unchanged — `--specs` does not alter the skill text itself
- SKILL.md files must not use bash parameter expansion (`${RALPH_SPEC_FILTER:+...}`) — Claude Code's backtick preprocessor does not support shell variable expansion syntax within `` !`command` `` blocks

## Constraints

- `--specs` is valid for both `plan` and `build` subcommands — it is not mode-specific
- Glob matching uses bash builtins only — no external dependencies (e.g., no `fnmatch`, no `grep -P`)
- The flag value is passed as a single string; the consuming commands (`peek`, `plan-status`, `plan-sync`) are responsible for splitting on `,` and matching

## Out of Scope

- Validating that patterns match existing spec files or task IDs
- Regex patterns (only shell glob syntax)
- Persistent filter configuration (e.g., storing a default filter in a config file)
- Filtering by fields other than spec-slug (e.g., priority, category, status)
