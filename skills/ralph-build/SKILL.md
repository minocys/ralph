---
name: ralph-build
description: Ralph build loop
argument-hint: [highest priority tasks]
---

# TASK
0a. Study `specs/*` with parallel Sonnet subagents to learn the application specifications.
0b. Study the highest priority tasks: $ARGUMENTS. `s`="open" are claimable (sorted by priority). Tasks with `s`="active" show what other agents are working on.

1. Your task is to implement functionality per the specifications using parallel subagnets. Follow the task list and choose the most important task to address. Claim the selected task via `task claim <id>`. If no claimable tasks remain, stop gracefully.
3. Search the codebase before implementing — confirm before assuming missing.
4. Implement the change.
5. Run tests for the changed code. If functionality is missing, add it as per the application specifications.
6. Mark completed steps with `task step-done <id> <seq>` as implementation progresses.
7. `git add -A` then `git commit` with a message describing the changes.
8. Run `task done <id> --result '{"commit":"<sha>"}'` where `<sha>` is the commit SHA from step 8.)
9. **IMPORTANT**: DO NOT START A NEW TASK.

## Rules

- Use Opus subagents when complex reasoning is needed (debugging, architectural decisions).
- Parallelize reads and searches aggressively with Sonnet subagents (up to 500 parallel).
- Only use a single Sonnet subagent for build/tests.
- When you discover issues, immediately create a task with a subagent (`task create <id> <title>`). When resolved, update the item as done. 
- When authoring documentation, capture the why — tests and implementation importance.
- Single sources of truth, no migrations/adapters. If tests unrelated to your work fail, resolve them as part of the increment.
- If `blocker_results` contains commit SHAs, run `git show <sha>` to review upstream changes before implementing.
- Implement functionality completely. Placeholders and stubs waste efforts and time redoing the same work.
- You may add extra logging if required to debug issues.
- When you learn something new about how to run the application, update @AGENTS.md using a subagent but keep it brief. For example if you run commands multiple times before learning the correct command then that file should be updated.
- Keep @AGENTS.md operational only — status updates belong in task steps and results.
- If you find inconsistencies in the specs/* then use an Opus subagent to update the specs.
- On failure, run `task fail <id> --reason "<text>"` to release the task for retry.
