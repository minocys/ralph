---
name: ralph-plan
description: Implementation planner that studies and breaks down specs into tasks for implementation.
---

# TASK
Study specs and codebase, then create or update IMPLEMENTATION_PLAN.json with prioritized tasks.

## Context

| Term             | Definition                                                    |
| ---------------- | ------------------------------------------------------------- |
| Job to be Done   | High-level user need or outcome                               |
| Topic of Concern | A distinct aspect or component within a JTBD                  |
| Spec             | Requirements doc for one topic of concern (`specs/<name>.md`) |
| Task             | Unit of work derived from comparing specs to code             |

## Steps
0a. Study `specs/*` with up to 250 parallel Sonnet subagents to learn the application specifications.
0b. Study @IMPLEMENTATION_PLAN.json (if present) to understand the plan so far.
0c. Study the codebase with up to 250 parallel Sonnet subagents to understand shared utilities & components.

1. Study @IMPLEMENTATION_PLAN.json (if present; it may be incorrect) and use up to 500 Sonnet subagents to study existing source code and compare it against `specs/*`. Use an Opus subagent to analyze findings, prioritize tasks, and create/update @IMPLEMENTATION_PLAN.json. **Take a TDD approach, writing tests with expected input/output pairs. Make each task the smallest possible unit of work. Aim for one small change per task!**  Study @IMPLEMENTATION_PLAN.json to determine starting point for research and keep it up to date with items considered complete/incomplete using subagents. .
2. Consider searching for TODO, minimal implementations, placeholders, skipped/flaky tests, and inconsistent patterns.
3. When complete, reply with: <promise>COMPLETE</promise>

**IMPORTANT**: Plan only. Do NOT implement anything. Do NOT assume functionality is missing; confirm with code search first. Prefer consolidated, idiomatic implementations there over ad-hoc copies.

### EXAMPLE IMPLEMENTATION_PLAN.json
````
[
  {
    "category": "setup",
    "description": "Initialize project structure and dependencies",
    "steps": [
      "Create project directory structure",
      "Initialize package.json or requirements",
      "Install required dependencies",
      "Verify files load correctly"
    ],
    "completed": false
  },
  {
    "category": "feature",
    "description": "Implement main navigation component",
    "steps": [
      "Create Navigation component",
      "Add responsive styling",
      "Implement mobile menu toggle"
    ],
    "completed": false
  }
]
````
