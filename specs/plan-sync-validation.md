# Plan-Sync Input Validation

The `task plan-sync` command validates JSONL input before processing and fails fast on malformed data, giving the calling agent a clear error to adjust and retry.

## Requirements

- Before processing any tasks, `task plan-sync` must pre-validate every stdin line
- Each line must be valid JSON — if `jq` fails to parse a line, the command must exit immediately with code 1 and print a descriptive error to stderr identifying the line number and content
- Each JSON object must contain a non-empty `id` field (string) — missing or empty `id` must be rejected with a descriptive error to stderr
- Each JSON object must contain a non-empty `t` (title) field (string) — missing or empty `t` must be rejected with a descriptive error to stderr
- If `p` (priority) is present, it must be a non-negative integer — non-integer or negative values must be rejected
- Validation must happen in a pre-parse pass before the database transaction begins — no partial writes on bad input
- The summary line (`inserted: N, updated: N, ...`) must only be printed on success — validation failures must not print the summary
- Error messages must include enough context for an LLM agent to fix the input (line number, field name, actual value)

## Constraints

- Validation uses `jq` for JSON parsing — no additional dependencies
- The existing behavior for valid input must not change
- Empty lines are still silently skipped (existing behavior)
- The pre-validation pass reads all stdin lines into memory before checking — this is acceptable since task counts are small

## Out of Scope

- Schema validation beyond `id`, `t`, and `p` (optional fields like `deps`, `steps`, `spec` are not validated)
- Validating that `deps` reference existing task IDs (referential integrity is a DB concern)
- Validating `spec` values against actual filenames in `specs/`
- Rate limiting or input size limits
