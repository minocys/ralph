---
name: ralph-build
description: Ralph build loop
---

# TASK
0a. Study `specs/*` with parallel Sonnet subagents to learn the application specifications.
0b. Study @IMPLEMENTATION_PLAN.json.

1. Pick the highest-priority incomplete task from @IMPLEMENTATION_PLAN.json. **IMPORTANT**: ONLY PICK ONE TASK. DO NOT START A NEW TASK AFTER THE CHOSEN TASK IS COMPLETED.
2. Search the codebase before implementing — confirm before assuming missing.
3. Implement the change.
4. Run tests for the changed code. If functionality is missing, add it as per the application specifications.
5. Update @IMPLEMENTATION_PLAN.json with findings and progress using a subagent.
6. `git add -A` then `git commit` with a message describing the changes.
7. Mark the task as completed. **IMPORTANT**:DO NOT START A NEW TASK.
8. Check if ALL tasks in @IMPLEMENTATION_PLAN.json are completed. If all tasks are complete, reply with <promise>Tastes Like Burning.</promise>.

## Rules

- Implement functionality completely. Placeholders and stubs waste efforts and time redoing the same work.
- Single sources of truth, no migrations/adapters. If tests unrelated to your work fail, resolve them as part of the increment.
- You may add extra logging if required to debug issues.
- When authoring documentation, capture the why — tests and implementation importance.
- Keep @IMPLEMENTATION_PLAN.json current with learnings using a subagent — future work depends on this to avoid duplicating efforts. Update especially after finishing your turn.
- When you learn something new about how to run the application, update @AGENTS.md using a subagent but keep it brief. For example if you run commands multiple times before learning the correct command then that file should be updated.
- Keep @AGENTS.md operational only — status updates and progress notes belong in `IMPLEMENTATION_PLAN.json`. A bloated AGENTS.md pollutes every future loop's context.
- When @IMPLEMENTATION_PLAN.json becomes large periodically clean out the items that are completed from the file using a subagent.
- If you find inconsistencies in the specs/* then use an Opus subagent to update the specs.
- For any bugs you notice, resolve them or document them in @IMPLEMENTATION_PLAN.json using a subagent even if it is unrelated to the current piece of work.
- Parallelize reads and searches aggressively with Sonnet subagents (up to 500 parallel).
- Use a single Sonnet subagent for build and test.
- Use Opus subagents for complex reasoning such as debugging and architectural decisions.
