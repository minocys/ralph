# Build Organization

Restructure `ralph-build/SKILL.md` to separate the sequential workflow from always-on rules, grouped by concern.

## Requirements

- The `## Steps` section must contain only the sequential per-iteration workflow:
  1. Study specs and IMPLEMENTATION_PLAN.json
  2. Pick the highest-priority incomplete task
  3. Search the codebase before implementing (confirm before assuming missing)
  4. Implement the change
  5. Run tests for the changed code
  6. Update IMPLEMENTATION_PLAN.json
  7. Stage changed files and commit
  8. Check if all tasks are complete — if yes, signal `<promise>Tastes Like Burning.</promise>`
- The `## Rules` section must contain non-sequential invariants, grouped into named concerns:
  - **Quality** — No placeholders or stubs; implement completely; resolve failing tests even if unrelated to current work
  - **Knowledge** — Keep IMPLEMENTATION_PLAN.json current with learnings; update AGENTS.md with operational commands only (no status or progress); clean completed items from the plan periodically
  - **Consistency** — If spec inconsistencies are found, use an Opus subagent to update specs; document discovered bugs in the plan even if unrelated
  - **Subagents** — Parallelize reads and searches aggressively with Sonnet subagents; use a single subagent for build and test; use Opus subagents for complex reasoning such as debugging and architectural decisions
- The rule groupings above replace the escalating-9s numbered items; no content should be lost, only reorganized
- Logging guidance ("you may add extra logging to debug") belongs under the Quality group

## Constraints

- Do not add new rules or remove existing ones — this is a reorganization of existing content
- Preserve the `<promise>Tastes Like Burning.</promise>` signal exactly as-is
- The step about `git add -A` should remain as-is for now (changing git strategy is out of scope)

## Out of Scope

- Changing subagent count language (addressed separately if needed)
- Modifying the completion detection in ralph.sh
- Changing git staging strategy
