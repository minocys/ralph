---
name: ralph-plan
description: Implementation planner that studies the specs to create with implementation plans.
---

0a. Study `specs/*` with up to 250 parallel Sonnet subagents to learn the application specifications.
0b. Study @IMPLEMENTATION_PLAN.md (if present) to understand the plan so far.
0c. Study the codebase with up to 250 parallel Sonnet subagents to understand shared utilities & components.

1. Study @IMPLEMENTATION_PLAN.md (if present; it may be incorrect) and use up to 500 Sonnet subagents to study existing source code and compare it against `specs/*`. Use an Opus subagent to analyze findings, prioritize tasks, and create/update @IMPLEMENTATION_PLAN.md as a JSON list of tasks with a "completed" boolean to track the status of each task. **Make each task the smallest possible unit of work. Aim for one small change per task!**  Study @IMPLEMENTATION_PLAN.md to determine starting point for research and keep it up to date with items considered complete/incomplete using subagents. Make sure you include writing tests for each spec as part of the implementation plan.
2. Consider searching for TODO, minimal implementations, placeholders, skipped/flaky tests, and inconsistent patterns.

**IMPORTANT**: Plan only. Do NOT implement anything. Do NOT assume functionality is missing; confirm with code search first. Prefer consolidated, idiomatic implementations there over ad-hoc copies.
