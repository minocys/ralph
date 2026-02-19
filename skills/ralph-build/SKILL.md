---
name: ralph-build
description: Ralph build loop
---

# TASK
0a. Study `specs/*` with parallel Sonnet subagents to learn the application specifications.
0b. Run `task plan-status` to see the current state of the task backlog.

1. Run `task claim` to atomically claim the highest-priority unblocked task. Parse the JSON output to get task fields, steps, and `blocker_results`. **IMPORTANT**: ONLY CLAIM ONE TASK. DO NOT START A NEW TASK AFTER THE CLAIMED TASK IS COMPLETED.
2. If `task claim` exits with code 2 (no eligible tasks), stop gracefully — do not continue.
3. If `blocker_results` contains commit SHAs, run `git show <sha>` to review upstream changes before implementing.
4. Search the codebase before implementing — confirm before assuming missing.
5. Implement the change.
6. Run tests for the changed code. If functionality is missing, add it as per the application specifications.
7. Mark completed steps with `task step-done <id> <seq>` as implementation progresses.
8. `git add -A` then `git commit` with a message describing the changes.
9. Run `task done <id> --result '{"commit":"<sha>"}'` where `<sha>` is the commit SHA from step 8. **IMPORTANT**: DO NOT START A NEW TASK.

## Rules

- Implement functionality completely. Placeholders and stubs waste efforts and time redoing the same work.
- Single sources of truth, no migrations/adapters. If tests unrelated to your work fail, resolve them as part of the increment.
- You may add extra logging if required to debug issues.
- When authoring documentation, capture the why — tests and implementation importance.
- Use `task step-done` to track progress within the current task.
- When you learn something new about how to run the application, update @AGENTS.md using a subagent but keep it brief. For example if you run commands multiple times before learning the correct command then that file should be updated.
- Keep @AGENTS.md operational only — status updates belong in task steps and results.
- If you find inconsistencies in the specs/* then use an Opus subagent to update the specs.
- For any bugs you notice, resolve them or run `task create <id> <title>` to log discovered bugs or new work even if unrelated to the current task.
- On failure, run `task fail <id> --reason "<text>"` to release the task for retry.
- Do not check overall task completion — ralph.sh owns loop control.
- Parallelize reads and searches aggressively with Sonnet subagents (up to 500 parallel).
- Use a single Sonnet subagent for build and test.
- Use Opus subagents for complex reasoning such as debugging and architectural decisions.
