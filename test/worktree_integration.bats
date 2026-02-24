#!/usr/bin/env bats
# test/worktree_integration.bats — worktree lifecycle integration in ralph.sh
#
# Verifies that ralph.sh:
#   1. Sources lib/worktree.sh and calls setup_worktree after setup_session
#   2. Passes --project-directory to claude when a worktree is active
#   3. Displays worktree path in print_banner
#   4. Cleans up worktree on exit via cleanup trap
#   5. Falls back gracefully when not in a git repo

load test_helper

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Create a task stub that returns a dummy task for peek
_create_task_stub() {
    cat > "$TEST_WORK_DIR/task" <<'STUB'
#!/bin/bash
case "$1" in
    agent)
        case "$2" in
            register) echo "a1b2"; exit 0 ;;
            deregister) exit 0 ;;
            *) exit 0 ;;
        esac
        ;;
    plan-status) echo "0 open, 0 active, 1 done, 0 blocked, 0 deleted"; exit 0 ;;
    peek) echo '## Task abc'; exit 0 ;;
    list) exit 0 ;;
    fail) exit 0 ;;
    *) exit 0 ;;
esac
STUB
    chmod +x "$TEST_WORK_DIR/task"
}

# Initialize a git repo in $TEST_WORK_DIR so worktree creation can succeed
_init_git_repo() {
    git -C "$TEST_WORK_DIR" init -b main >/dev/null 2>&1
    git -C "$TEST_WORK_DIR" config user.email "test@test.com"
    git -C "$TEST_WORK_DIR" config user.name "Test"
    git -C "$TEST_WORK_DIR" add -A
    git -C "$TEST_WORK_DIR" commit -m "initial" --allow-empty >/dev/null 2>&1
}

# Override default setup: copy ralph project into a test dir
setup() {
    TEST_WORK_DIR="$(mktemp -d)"
    STUB_DIR="$(mktemp -d)"
    export TEST_WORK_DIR STUB_DIR

    # Copy ralph.sh, lib/, and models.json into the test work directory
    cp "$SCRIPT_DIR/ralph.sh" "$TEST_WORK_DIR/ralph.sh"
    chmod +x "$TEST_WORK_DIR/ralph.sh"
    cp -r "$SCRIPT_DIR/lib" "$TEST_WORK_DIR/lib"
    cp "$SCRIPT_DIR/models.json" "$TEST_WORK_DIR/models.json"

    # Minimal specs/ directory so preflight passes
    mkdir -p "$TEST_WORK_DIR/specs"
    echo "# dummy spec" > "$TEST_WORK_DIR/specs/dummy.md"

    _create_task_stub

    # Claude stub that logs invocation args
    cat > "$STUB_DIR/claude" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" > "$TEST_WORK_DIR/claude_args.log"
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"done"}]}}'
echo '{"type":"result","subtype":"success","total_cost_usd":0.01,"num_turns":1}'
exit 0
STUB
    chmod +x "$STUB_DIR/claude"

    # Docker/pg_isready stubs
    cat > "$STUB_DIR/docker" <<'DOCKERSTUB'
#!/bin/bash
case "$1" in
    compose)
        if [ "$2" = "version" ]; then echo "Docker Compose version v2.24.0"; fi
        exit 0 ;;
    inspect)
        if [ "$3" = "{{.State.Running}}" ]; then echo "true"
        elif [ "$3" = "{{.State.Health.Status}}" ]; then echo "healthy"; fi
        exit 0 ;;
esac
exit 0
DOCKERSTUB
    chmod +x "$STUB_DIR/docker"
    cat > "$STUB_DIR/pg_isready" <<'PGSTUB'
#!/bin/bash
exit 0
PGSTUB
    chmod +x "$STUB_DIR/pg_isready"

    export ORIGINAL_PATH="$PATH"
    export PATH="$STUB_DIR:$PATH"

    cd "$TEST_WORK_DIR"
}

teardown() {
    if [[ -n "${ORIGINAL_PATH:-}" ]]; then
        export PATH="$ORIGINAL_PATH"
    fi
    [[ -d "${TEST_WORK_DIR:-}" ]] && rm -rf "$TEST_WORK_DIR"
    [[ -d "${STUB_DIR:-}" ]] && rm -rf "$STUB_DIR"
}

# ---------------------------------------------------------------------------
# Worktree creation in git repo
# ---------------------------------------------------------------------------

@test "ralph creates worktree when project is a git repo" {
    _init_git_repo

    run "$TEST_WORK_DIR/ralph.sh" -n 1
    assert_success

    # The branch ralph/a1b2 should have been created
    run git -C "$TEST_WORK_DIR" branch --list "ralph/a1b2"
    assert_output --partial "ralph/a1b2"
}

@test "ralph passes --project-directory to claude when worktree is active" {
    _init_git_repo

    run "$TEST_WORK_DIR/ralph.sh" -n 1
    assert_success

    [ -f "$TEST_WORK_DIR/claude_args.log" ]
    run cat "$TEST_WORK_DIR/claude_args.log"
    assert_output --partial "--project-directory"
    assert_output --partial ".ralph/worktrees/"
}

@test "ralph banner shows worktree path when active" {
    _init_git_repo

    run "$TEST_WORK_DIR/ralph.sh" -n 1
    assert_success
    assert_output --partial "Work:"
    assert_output --partial ".ralph/worktrees/"
}

@test "ralph cleans up worktree on normal exit" {
    _init_git_repo

    run "$TEST_WORK_DIR/ralph.sh" -n 1
    assert_success

    # Worktree directory should be removed after exit
    run ls "$TEST_WORK_DIR/.ralph/worktrees/"
    refute_output --partial "a1b2"
}

# ---------------------------------------------------------------------------
# Fallback when not a git repo
# ---------------------------------------------------------------------------

@test "ralph falls back gracefully when not in a git repo" {
    # Don't init git repo — TEST_WORK_DIR is a plain directory

    # Need a git stub that handles branch --show-current (for setup_session)
    # but fails rev-parse (for worktree detection)
    cat > "$STUB_DIR/git" <<'GITSTUB'
#!/bin/bash
case "$1" in
    branch) echo "main"; exit 0 ;;
    -C)
        shift
        shift  # skip the path
        case "$1" in
            rev-parse) exit 1 ;;  # not a git repo
            *) exit 0 ;;
        esac
        ;;
    rev-parse) exit 1 ;;
    *) exit 0 ;;
esac
GITSTUB
    chmod +x "$STUB_DIR/git"

    run "$TEST_WORK_DIR/ralph.sh" -n 1
    assert_success

    # Should NOT have --project-directory in claude args
    [ -f "$TEST_WORK_DIR/claude_args.log" ]
    run cat "$TEST_WORK_DIR/claude_args.log"
    refute_output --partial "--project-directory"
}

@test "ralph banner does not show Work line when no worktree" {
    # Use a git stub for non-git-repo
    cat > "$STUB_DIR/git" <<'GITSTUB'
#!/bin/bash
case "$1" in
    branch) echo "main"; exit 0 ;;
    -C)
        shift; shift
        case "$1" in
            rev-parse) exit 1 ;;
            *) exit 0 ;;
        esac
        ;;
    rev-parse) exit 1 ;;
    *) exit 0 ;;
esac
GITSTUB
    chmod +x "$STUB_DIR/git"

    run "$TEST_WORK_DIR/ralph.sh" -n 1
    assert_success
    refute_output --partial "Work:"
}

# ---------------------------------------------------------------------------
# Plan mode (no agent ID) falls back
# ---------------------------------------------------------------------------

@test "plan mode falls back when no agent ID is available" {
    _init_git_repo

    # Claude stub that emits the promise sentinel for plan mode completion
    cat > "$STUB_DIR/claude" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" > "$TEST_WORK_DIR/claude_args.log"
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"<promise>Tastes Like Burning.</promise>"}]}}'
echo '{"type":"result","subtype":"success","total_cost_usd":0.01,"num_turns":1}'
exit 0
STUB
    chmod +x "$STUB_DIR/claude"

    run "$TEST_WORK_DIR/ralph.sh" --plan -n 1
    assert_success

    # Plan mode has no AGENT_ID, so setup_worktree receives empty args
    # create_worktree should fail, and fallback to project dir
    [ -f "$TEST_WORK_DIR/claude_args.log" ]
    run cat "$TEST_WORK_DIR/claude_args.log"
    refute_output --partial "--project-directory"
}
