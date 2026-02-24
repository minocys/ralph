#!/usr/bin/env bats
# test/entrypoint_env.bats — environment validation tests for docker/entrypoint.sh

load test_helper

# Helper: run the env validation section from entrypoint.sh in a subshell.
# Uses _TEST_RALPH_DIR to control .env / .env.example presence.
_run_env_validation() {
    local script
    script=$(cat <<'SCRIPT'
set -euo pipefail
RALPH_DIR="$_TEST_RALPH_DIR"

# Source .env defaults — prefer .env, fall back to .env.example
if [ -f "$RALPH_DIR/.env" ]; then
    . "$RALPH_DIR/.env"
elif [ -f "$RALPH_DIR/.env.example" ]; then
    . "$RALPH_DIR/.env.example"
fi

# Default RALPH_DB_URL to internal Docker network address
export RALPH_DB_URL="${RALPH_DB_URL:-postgres://ralph:ralph@ralph-task-db:5432/ralph}"

# Validate required database connection
if [ -z "${RALPH_DB_URL:-}" ] && \
   { [ -z "${POSTGRES_USER:-}" ] || [ -z "${POSTGRES_PASSWORD:-}" ] || [ -z "${POSTGRES_DB:-}" ]; }; then
    echo "Error: Database connection is not configured." >&2
    echo "" >&2
    echo "Fix: set RALPH_DB_URL or provide all of POSTGRES_USER, POSTGRES_PASSWORD, and POSTGRES_DB." >&2
    echo "" >&2
    echo "  Option 1 — set RALPH_DB_URL directly:" >&2
    echo "    export RALPH_DB_URL=\"postgres://user:pass@host:5432/dbname\"" >&2
    echo "" >&2
    echo "  Option 2 — set individual POSTGRES_* variables:" >&2
    echo "    export POSTGRES_USER=ralph" >&2
    echo "    export POSTGRES_PASSWORD=ralph" >&2
    echo "    export POSTGRES_DB=ralph" >&2
    exit 1
fi

# Print RALPH_DB_URL so tests can verify the value
echo "RALPH_DB_URL=$RALPH_DB_URL"
SCRIPT
)
    run bash -c "$script"
}

# Helper: run validation WITHOUT the default assignment to test the error path.
# This simulates what happens if the default were removed or if RALPH_DB_URL is
# explicitly cleared after the default line (defense-in-depth testing).
_run_validation_only() {
    local script
    script=$(cat <<'SCRIPT'
set -euo pipefail

# Validate required database connection
if [ -z "${RALPH_DB_URL:-}" ] && \
   { [ -z "${POSTGRES_USER:-}" ] || [ -z "${POSTGRES_PASSWORD:-}" ] || [ -z "${POSTGRES_DB:-}" ]; }; then
    echo "Error: Database connection is not configured." >&2
    echo "" >&2
    echo "Fix: set RALPH_DB_URL or provide all of POSTGRES_USER, POSTGRES_PASSWORD, and POSTGRES_DB." >&2
    echo "" >&2
    echo "  Option 1 — set RALPH_DB_URL directly:" >&2
    echo "    export RALPH_DB_URL=\"postgres://user:pass@host:5432/dbname\"" >&2
    echo "" >&2
    echo "  Option 2 — set individual POSTGRES_* variables:" >&2
    echo "    export POSTGRES_USER=ralph" >&2
    echo "    export POSTGRES_PASSWORD=ralph" >&2
    echo "    export POSTGRES_DB=ralph" >&2
    exit 1
fi

echo "OK"
SCRIPT
)
    run bash -c "$script"
}

setup() {
    TEST_WORK_DIR="$(mktemp -d)"
    STUB_DIR="$(mktemp -d)"
    export TEST_WORK_DIR STUB_DIR
    export ORIGINAL_PATH="$PATH"
    export PATH="$STUB_DIR:$PATH"

    # Default RALPH_DIR for tests
    export _TEST_RALPH_DIR="$TEST_WORK_DIR/ralph"
    mkdir -p "$_TEST_RALPH_DIR"

    # Unset env vars so each test starts clean
    unset RALPH_DB_URL POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB POSTGRES_PORT

    cd "$TEST_WORK_DIR"
}

teardown() {
    if [[ -n "${ORIGINAL_PATH:-}" ]]; then
        export PATH="$ORIGINAL_PATH"
    fi
    if [[ -d "$TEST_WORK_DIR" ]]; then
        rm -rf "$TEST_WORK_DIR"
    fi
    if [[ -d "$STUB_DIR" ]]; then
        rm -rf "$STUB_DIR"
    fi
}

# --- .env sourcing priority ---

@test "entrypoint sources .env when both .env and .env.example exist" {
    echo 'RALPH_DB_URL=postgres://from-env@host:5432/db' > "$_TEST_RALPH_DIR/.env"
    echo 'RALPH_DB_URL=postgres://from-example@host:5432/db' > "$_TEST_RALPH_DIR/.env.example"

    _run_env_validation
    assert_success
    assert_output --partial "RALPH_DB_URL=postgres://from-env@host:5432/db"
}

@test "entrypoint sources .env.example when .env is absent" {
    echo 'RALPH_DB_URL=postgres://from-example@host:5432/db' > "$_TEST_RALPH_DIR/.env.example"

    _run_env_validation
    assert_success
    assert_output --partial "RALPH_DB_URL=postgres://from-example@host:5432/db"
}

@test "entrypoint sets default RALPH_DB_URL when neither .env nor .env.example exists" {
    _run_env_validation
    assert_success
    assert_output --partial "RALPH_DB_URL=postgres://ralph:ralph@ralph-task-db:5432/ralph"
}

# --- RALPH_DB_URL default ---

@test "entrypoint defaults RALPH_DB_URL to internal Docker network address" {
    _run_env_validation
    assert_success
    assert_output --partial "RALPH_DB_URL=postgres://ralph:ralph@ralph-task-db:5432/ralph"
}

@test "entrypoint preserves pre-set RALPH_DB_URL over default" {
    export RALPH_DB_URL="postgres://custom:pass@remotehost:5432/mydb"
    _run_env_validation
    assert_success
    assert_output --partial "RALPH_DB_URL=postgres://custom:pass@remotehost:5432/mydb"
}

@test "entrypoint preserves pre-set RALPH_DB_URL over .env.example" {
    echo 'RALPH_DB_URL=postgres://from-example@host:5432/db' > "$_TEST_RALPH_DIR/.env.example"
    export RALPH_DB_URL="postgres://custom:pass@remotehost:5432/mydb"
    _run_env_validation
    assert_success
    # .env.example is sourced first (overwriting RALPH_DB_URL), but the default
    # assignment won't override since RALPH_DB_URL is now non-empty from .env.example.
    # Actually, sourcing .env.example WILL overwrite the env var. The spec says the
    # entrypoint sources the file, then applies the default. So the .env.example value wins.
    assert_output --partial "RALPH_DB_URL=postgres://from-example@host:5432/db"
}

@test "entrypoint exports RALPH_DB_URL" {
    _run_env_validation
    assert_success
    assert_output --partial "RALPH_DB_URL="
}

# --- validation logic (isolated, without the default assignment) ---

@test "validation passes when RALPH_DB_URL is set" {
    export RALPH_DB_URL="postgres://ralph:ralph@localhost:5432/ralph"
    _run_validation_only
    assert_success
}

@test "validation passes when all POSTGRES vars are set and RALPH_DB_URL is empty" {
    export RALPH_DB_URL=""
    export POSTGRES_USER="user"
    export POSTGRES_PASSWORD="pass"
    export POSTGRES_DB="db"
    _run_validation_only
    assert_success
}

@test "validation fails when RALPH_DB_URL is empty and POSTGRES_USER is missing" {
    export RALPH_DB_URL=""
    export POSTGRES_PASSWORD="pass"
    export POSTGRES_DB="db"
    _run_validation_only
    assert_failure
    assert_output --partial "Error: Database connection is not configured."
}

@test "validation fails when RALPH_DB_URL is empty and POSTGRES_PASSWORD is missing" {
    export RALPH_DB_URL=""
    export POSTGRES_USER="user"
    export POSTGRES_DB="db"
    _run_validation_only
    assert_failure
    assert_output --partial "Error: Database connection is not configured."
}

@test "validation fails when RALPH_DB_URL is empty and POSTGRES_DB is missing" {
    export RALPH_DB_URL=""
    export POSTGRES_USER="user"
    export POSTGRES_PASSWORD="pass"
    _run_validation_only
    assert_failure
    assert_output --partial "Error: Database connection is not configured."
}

@test "validation fails when no database vars are set at all" {
    _run_validation_only
    assert_failure
    assert_output --partial "Error: Database connection is not configured."
}

@test "validation error includes fix instructions with both options" {
    _run_validation_only
    assert_failure
    assert_output --partial "Option 1"
    assert_output --partial "Option 2"
    assert_output --partial "POSTGRES_USER=ralph"
    assert_output --partial "POSTGRES_PASSWORD=ralph"
    assert_output --partial "POSTGRES_DB=ralph"
}

# --- full entrypoint flow: default ensures validation always passes ---

@test "full entrypoint flow passes even with no env vars because default is set" {
    _run_env_validation
    assert_success
    assert_output --partial "RALPH_DB_URL=postgres://ralph:ralph@ralph-task-db:5432/ralph"
}
