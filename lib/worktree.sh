#!/bin/bash
# lib/worktree.sh — git worktree isolation for concurrent ralph loops
#
# Provides:
#   create_worktree()   — create a git worktree for isolated loop execution
#   cleanup_worktree()  — remove a git worktree (best-effort, preserves branch)
#
# Globals used: none (pure function, uses parameters only)

# create_worktree: create a git worktree for an isolated ralph loop session
#
# Usage: create_worktree <session-id> <agent-id>
#
# Creates .ralph/worktrees/<session-id>/ with a new branch ralph/<agent-id>
# branching from the current HEAD. Prints the worktree path to stdout on
# success and logs it to stderr. Returns non-zero on failure.
create_worktree() {
    local session_id="$1"
    local agent_id="$2"

    if [ -z "$session_id" ] || [ -z "$agent_id" ]; then
        echo "Error: create_worktree requires <session-id> and <agent-id>" >&2
        return 1
    fi

    local worktree_dir=".ralph/worktrees/${session_id}"
    local branch_name="ralph/${agent_id}"

    mkdir -p .ralph/worktrees/

    if ! git worktree add "$worktree_dir" -b "$branch_name" 2>&2; then
        echo "Error: failed to create worktree at $worktree_dir" >&2
        return 1
    fi

    echo "worktree: created $worktree_dir on branch $branch_name" >&2
    echo "$worktree_dir"
    return 0
}

# cleanup_worktree: remove a git worktree (best-effort, preserves branch)
#
# Usage: cleanup_worktree <worktree-path>
#
# Removes the worktree at the given path using git worktree remove --force.
# The branch is NOT deleted — it is preserved for user review and manual merge.
# Logs removal to stderr. Returns 0 even if removal fails (best-effort).
cleanup_worktree() {
    local worktree_path="$1"

    if [ -z "$worktree_path" ]; then
        echo "Error: cleanup_worktree requires <worktree-path>" >&2
        return 0
    fi

    if git worktree remove --force "$worktree_path" 2>&2; then
        echo "worktree: removed $worktree_path" >&2
    else
        echo "worktree: failed to remove $worktree_path (best-effort, continuing)" >&2
    fi

    return 0
}
