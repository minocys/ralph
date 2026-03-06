#!/bin/bash
# lib/docker.sh — Docker sandbox helpers
#
# Functions:
#   derive_sandbox_name  - Derive deterministic sandbox name from repo+branch
#   check_sandbox_state  - Check sandbox state (running, stopped, or not found)

# derive_sandbox_name: produce a deterministic sandbox name from repo+branch
# Pattern: ralph-{owner}-{repo}-{branch}, sanitized and truncated to 63 chars
derive_sandbox_name() {
    local repo branch owner_repo name

    # Repo: env var override or git remote
    if [ -n "${RALPH_SCOPE_REPO:-}" ]; then
        owner_repo="$RALPH_SCOPE_REPO"
    else
        local remote_url
        remote_url="$(git remote get-url origin 2>/dev/null)" || {
            echo "Error: no git remote \"origin\" found" >&2
            return 1
        }
        # Strip .git suffix
        remote_url="${remote_url%.git}"
        # Extract owner/repo from URL
        if [[ "$remote_url" =~ ^[a-zA-Z]+:// ]]; then
            # URL scheme format: https://host/owner/repo or ssh://git@host/owner/repo
            local path="${remote_url#*://}"  # remove scheme
            owner_repo="${path#*/}"          # remove host
        else
            # SCP-like SSH format: git@github.com:owner/repo
            owner_repo="${remote_url##*:}"
        fi
    fi

    # Branch: env var override or git branch
    if [ -n "${RALPH_SCOPE_BRANCH:-}" ]; then
        branch="$RALPH_SCOPE_BRANCH"
    else
        branch="$(git branch --show-current 2>/dev/null)" || {
            echo "Error: detached HEAD state. Checkout a branch first" >&2
            return 1
        }
        if [ -z "$branch" ]; then
            echo "Error: detached HEAD state. Checkout a branch first" >&2
            return 1
        fi
    fi

    # Replace slash between owner/repo with dash
    owner_repo="${owner_repo//\//-}"

    # Build raw name
    name="ralph-${owner_repo}-${branch}"

    # Sanitize: replace non-alphanumeric chars with dashes
    name="$(echo "$name" | tr -c 'a-zA-Z0-9' '-')"

    # Collapse consecutive dashes
    name="$(echo "$name" | sed 's/--*/-/g')"

    # Strip leading and trailing dashes
    name="$(echo "$name" | sed 's/^-//;s/-$//')"

    # Truncate to 63 chars
    name="${name:0:63}"

    # Ensure no trailing dash after truncation
    name="${name%-}"

    echo "$name"
}

# check_sandbox_state: check if a sandbox exists and its state
# Returns: "running", "stopped", or "" (not found)
check_sandbox_state() {
    local name="$1"
    local state

    # Query docker sandbox ls for the named sandbox
    state="$(docker sandbox ls --json 2>/dev/null | \
        jq -r --arg name "$name" '.[] | select(.Name == $name) | .Status' 2>/dev/null)" || true

    case "$state" in
        running|Running)
            echo "running"
            ;;
        stopped|Stopped|exited|Exited)
            echo "stopped"
            ;;
        *)
            echo ""
            ;;
    esac
}
