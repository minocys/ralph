---
name: ralph-plan
description: Implementation planner that studies and breaks down specs into tasks for implementation.
argument-hint: [current-plan-dag]
---

# TASK
0a. Study `specs/*` with up to 250 parallel Sonnet subagents to learn the application specifications.
0b. Study the current plan DAG (if present) to understand the plan so far: $ARGUMENTS[0]
0c. Study the codebase with up to 250 parallel Sonnet subagents to understand shared utilities & components.

1. Review the current task DAG snapshot provided as input and use up to 500 Sonnet subagents to study existing source code and compare it against `specs/*`.
2. Use an Opus subagent to analyze findings, prioritize tasks, and emit JSONL to `task plan-sync` (piped via stdin). **Make each task the smallest possible unit of work. Aim for one small change per task!** Within each task, try to take a TDD approach, writing unit with expected input/output pairs or property tests.
   - Task IDs must use `{spec-slug}/{seq}` format (e.g., `task-cli/01`) where `spec-slug` matches the spec filename without `.md`
   - Every task must set `spec_ref` to the source spec filename (e.g., `task-cli.md`)
   - Priority must be an integer: 0=critical, 1=high, 2=medium, 3=low
   - Dependencies between tasks must be expressed via the `deps` field when task B requires task A's output
   - See `specs/task-cli.md` § JSONL Format for field names and structure
3. Consider searching for TODO, minimal implementations, placeholders, skipped/flaky tests, and inconsistent patterns.
4. When complete, reply with: <promise>Tastes Like Burning.</promise>

**IMPORTANT**: Plan only. Do NOT implement anything. Do NOT assume functionality is missing; confirm with code search first. Prefer consolidated, idiomatic implementations there over ad-hoc copies.

Consider missing elements and plan accordingly. If an element is missing, search first to confirm it doesn't exist, then if needed author the specification at `specs/FILENAME.md`. Spec filenames must be short kebab-case slugs (e.g., `task-cli.md`, `build-loop-control.md`) because they become `spec_ref` values and task ID prefixes (`{spec-slug}/{seq}`). If you create a new element then emit the plan as JSONL to `task plan-sync` using a subagent.

## Context

| Term             | Definition                                                    |
| ---------------- | ------------------------------------------------------------- |
| Job to be Done   | High-level user need or outcome                               |
| Topic of Concern | A distinct aspect or component within a JTBD                  |
| Spec             | Requirements doc for one topic of concern (`specs/<name>.md`) |
| Task             | Unit of work derived from comparing specs to code             |

