# Git Worktree Isolation

## Overview

When multiple ralph loops run concurrently against the same project (e.g., two `docker exec` sessions targeting the same mounted repository), concurrent file edits would conflict. Git worktrees provide isolated working directories backed by the same repository, allowing each loop to operate on its own branch and file tree without interfering with others.

## Requirements

- When a ralph loop starts inside the container and detects that the project directory is a git repository, it creates a new git worktree for that loop session.
- Worktrees are created in a `.ralph/worktrees/` directory relative to the project root (e.g., `/workspace/project/.ralph/worktrees/<session-id>/`).
- Each worktree is checked out to a new branch named `ralph/<agent-id>` (using the 4-char hex agent ID from agent registration). The branch is created from the current HEAD of the project's main working tree.
- The ralph loop operates entirely within the worktree directory — all Claude Code file edits, git commits, and reads happen in the worktree, not the main working tree.
- On loop exit (normal completion, signal, or crash-safety fallback), the worktree is removed via `git worktree remove`. The branch is preserved so the user can review and merge it manually.
- If worktree creation fails (e.g., git is not available, not a git repo, or disk full), the loop falls back to operating directly in the project directory with a warning message. This fallback preserves single-loop usability.
- The `.ralph/worktrees/` directory is added to `.gitignore` so worktree artifacts are never committed.
- Worktree creation and removal are logged to stderr so the user can see the paths in the ralph banner and exit output.

## Constraints

- Worktrees share the same `.git` directory as the main working tree. Concurrent worktree operations (create, remove) on the same repo must not corrupt the git state. Git itself provides this safety via lock files.
- Worktree branch names must not collide. Using the agent ID (unique per session) as a suffix prevents this.
- The worktree working directory must be passed to Claude Code as the project root so all file operations target the worktree, not the original mount.
- Worktree creation requires git 2.15+ (for `git worktree add` with branch creation). The container image must include a sufficiently recent git version (Alpine's default git package satisfies this).

## Out of Scope

- Automatic merging of worktree branches into main — the user merges manually.
- Conflict detection or resolution between concurrent worktree branches.
- Worktree reuse across loop iterations (each iteration of the outer ralph loop uses the same worktree; a new worktree is only created per `docker exec` session).
- Submodule handling within worktrees.
- Worktree cleanup for orphaned worktrees from crashed sessions (users can run `git worktree prune` manually).
