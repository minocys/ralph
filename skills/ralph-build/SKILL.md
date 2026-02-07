---
name: ralph-build
description: Ralph build loop
---

# TASK
Implement functionality per specifications using parallel subagents.

## Context

| Term             | Definition                                                    |
| ---------------- | ------------------------------------------------------------- |
| Job to be Done   | High-level user need or outcome                               |
| Topic of Concern | A distinct aspect or component within a JTBD                  |
| Spec             | Requirements doc for one topic of concern (`specs/<name>.md`) |
| Task             | Unit of work derived from comparing specs to code             |

## Steps
0a. Study `specs/*` with up to 500 parallel Sonnet subagents to learn the application specifications.
0b. Study @IMPLEMENTATION_PLAN.json.

1. Your task is to implement functionality per the specifications using parallel subagents. Follow @IMPLEMENTATION_PLAN.json and choose the most important incomplete item to address. Before making changes, search the codebase (don't assume not implemented) using Sonnet subagents. You may use up to 500 parallel Sonnet subagents for searches/reads and only 1 Sonnet subagent for build/tests. Use Opus subagents when complex reasoning is needed (debugging, architectural decisions) **ONLY PICK ONE TASK**.
2. After implementing functionality or resolving problems, run the tests for that unit of code that was improved. If functionality is missing then it's your job to add it as per the application specifications.
3. When you discover issues, immediately update @IMPLEMENTATION_PLAN.json with your findings using a subagent. When resolved, update and remove the item.
4. When the tests pass, update @IMPLEMENTATION_PLAN.json, then `git add -A` then `git commit` with a message describing the changes.
5. After completing a task, mark the task as completed. **DO NOT START A NEW TASK, ONLY WORK ON ONE TASK.**
6. Check if ALL tasks in @IMPLEMNTATION_PLAN.json are completed. If all tasks are complete, reply with <promise>Tastes Like Burning.</promise>.

## Rules
- Important: When authoring documentation, capture the why — tests and implementation importance.
- Important: Single sources of truth, no migrations/adapters. If tests unrelated to your work fail, resolve them as part of the increment.
- You may add extra logging if required to debug issues.
- Keep @IMPLEMENTATION_PLAN.json current with learnings using a subagent — future work depends on this to avoid duplicating efforts. Update especially after finishing your turn.
- When you learn something new about how to run the application, update @AGENTS.md using a subagent but keep it brief. For example if you run commands multiple times before learning the correct command then that file should be updated.
- For any bugs you notice, resolve them or document them in @IMPLEMENTATION_PLAN.json using a subagent even if it is unrelated to the current piece of work.
- Implement functionality completely. Placeholders and stubs waste efforts and time redoing the same work.
- When @IMPLEMENTATION_PLAN.json becomes large periodically clean out the items that are completed from the file using a subagent.
- If you find inconsistencies in the specs/* then use an Opus 4.6 subagent requested to update the specs.
- IMPORTANT: Keep @AGENTS.md operational only — status updates and progress notes belong in `IMPLEMENTATION_PLAN.json`. A bloated AGENTS.md pollutes every future loop's context.
