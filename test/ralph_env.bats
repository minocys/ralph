#!/usr/bin/env bats
# test/ralph_env.bats — environment and database configuration tests
#
# Verifies that the database path is derived from git root via
# git rev-parse --show-toplevel, and that legacy PostgreSQL/Docker
# references have been removed.

load test_helper

# ---------------------------------------------------------------------------
# Setup/teardown — each test gets a temp directory and clean env
# ---------------------------------------------------------------------------
setup() {
    common_setup
}

teardown() {
    common_teardown
}

# ---------------------------------------------------------------------------
# Database path derivation from git root
# ---------------------------------------------------------------------------
@test "lib/task derives DB path from git root" {
    cd "$TEST_WORK_DIR"
    run "$SCRIPT_DIR/lib/task" list
    assert_success
    assert [ -d "$TEST_WORK_DIR/.ralph" ]
}

@test "lib/task ignores RALPH_DB_PATH env var" {
    export RALPH_DB_PATH="$TEST_WORK_DIR/custom/tasks.db"
    cd "$TEST_WORK_DIR"
    run "$SCRIPT_DIR/lib/task" list
    assert_success
    # .ralph/ should be at git root, not at the custom path
    assert [ -d "$TEST_WORK_DIR/.ralph" ]
    assert [ ! -d "$TEST_WORK_DIR/custom" ]
}

@test "lib/task fails outside a git repo" {
    local NON_GIT_DIR
    NON_GIT_DIR="$(mktemp -d)"
    cd "$NON_GIT_DIR"
    run "$SCRIPT_DIR/lib/task" list
    assert_failure
    assert_output --partial "not inside a git repository"
    rm -rf "$NON_GIT_DIR"
}

# ---------------------------------------------------------------------------
# .env.example correctness
# ---------------------------------------------------------------------------
@test ".env.example has no RALPH_DB_PATH override" {
    run grep "^RALPH_DB_PATH=" "$SCRIPT_DIR/.env.example"
    assert_failure
}

@test ".env.example has no POSTGRES references" {
    run grep -i "POSTGRES" "$SCRIPT_DIR/.env.example"
    assert_failure
}

@test ".env.example has no RALPH_DB_URL reference" {
    run grep "RALPH_DB_URL" "$SCRIPT_DIR/.env.example"
    assert_failure
}

# ---------------------------------------------------------------------------
# No PostgreSQL references in active code
# ---------------------------------------------------------------------------
@test "lib/task has no RALPH_DB_URL references" {
    run grep "RALPH_DB_URL" "$SCRIPT_DIR/lib/task"
    assert_failure
}

@test "lib/task has no POSTGRES references" {
    run grep -i "POSTGRES" "$SCRIPT_DIR/lib/task"
    assert_failure
}

@test "ralph.sh has no RALPH_DB_URL references" {
    run grep "RALPH_DB_URL" "$SCRIPT_DIR/ralph.sh"
    assert_failure
}

@test "ralph.sh has no POSTGRES references" {
    run grep -i "POSTGRES" "$SCRIPT_DIR/ralph.sh"
    assert_failure
}

@test "test_helper.bash has no RALPH_DB_URL references" {
    run grep "RALPH_DB_URL" "$SCRIPT_DIR/test/test_helper.bash"
    assert_failure
}

@test "test_helper.bash has no POSTGRES references" {
    run grep -i "POSTGRES" "$SCRIPT_DIR/test/test_helper.bash"
    assert_failure
}

# ---------------------------------------------------------------------------
# No PostgreSQL/Docker-compose references in active code
# (Docker sandbox support is intentional — see docker-sandbox-dispatch spec)
# ---------------------------------------------------------------------------
@test "ralph.sh has no docker-compose references" {
    run grep -i "docker-compose\|docker compose" "$SCRIPT_DIR/ralph.sh"
    assert_failure
}

@test "test_helper.bash has no Docker or pg_isready stubs" {
    run grep -i "docker\|pg_isready" "$SCRIPT_DIR/test/test_helper.bash"
    assert_failure
}

@test "lib/docker.sh exists for sandbox support" {
    assert_file_exists "$SCRIPT_DIR/lib/docker.sh"
}

@test "lib/docker.sh defines derive_sandbox_name function" {
    run grep -E '^derive_sandbox_name\(\)' "$SCRIPT_DIR/lib/docker.sh"
    assert_success
}

@test "lib/docker.sh defines check_sandbox_state function" {
    run grep -E '^check_sandbox_state\(\)' "$SCRIPT_DIR/lib/docker.sh"
    assert_success
}

@test "lib/docker.sh is sourceable without errors" {
    # Source docker.sh in a subshell to verify it has valid bash syntax.
    # Override docker and git commands to prevent side effects.
    run bash -c '
        docker() { :; }
        git() { :; }
        export -f docker git
        source "'"$SCRIPT_DIR/lib/docker.sh"'"
    '
    assert_success
}
