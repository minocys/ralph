#!/usr/bin/env bats
# test/ralph_env.bats — ensure_env_file() tests for ralph.sh

load test_helper

# Helper: extract and evaluate ensure_env_file() from lib/docker.sh
# Uses PROJECT_DIR (unmodified SCRIPT_DIR from test_helper) to find lib/docker.sh,
# then each test sets SCRIPT_DIR to a temp dir for the function to operate on.
_load_ensure_env_file() {
    eval "$(sed -n '/^ensure_env_file()/,/^}/p' "$PROJECT_DIR/lib/docker.sh")"
}

setup() {
    # Run default test_helper setup first
    TEST_WORK_DIR="$(mktemp -d)"
    mkdir -p "$TEST_WORK_DIR/specs"
    echo "# dummy spec" > "$TEST_WORK_DIR/specs/dummy.md"
    export TEST_WORK_DIR

    # Preserve the real project dir for loading functions from ralph.sh
    PROJECT_DIR="$SCRIPT_DIR"
    export PROJECT_DIR

    cd "$TEST_WORK_DIR"
}

teardown() {
    if [[ -d "$TEST_WORK_DIR" ]]; then
        rm -rf "$TEST_WORK_DIR"
    fi
}

# --- ensure_env_file tests ---

@test "ensure_env_file copies .env.example to .env when .env is missing" {
    printf 'POSTGRES_USER=ralph\nPOSTGRES_PASSWORD=ralph\nPOSTGRES_DB=ralph\nPOSTGRES_PORT=5432\nRALPH_DB_URL=postgres://ralph:ralph@localhost:5432/ralph\n' > "$TEST_WORK_DIR/.env.example"

    SCRIPT_DIR="$TEST_WORK_DIR"
    _load_ensure_env_file

    run ensure_env_file
    assert_success
    assert_file_exists "$TEST_WORK_DIR/.env"
    assert_output --partial "Created .env from .env.example"
}

@test "ensure_env_file .env content matches .env.example" {
    printf 'POSTGRES_USER=ralph\nRALPH_DB_URL=postgres://ralph:ralph@localhost:5432/ralph\n' > "$TEST_WORK_DIR/.env.example"

    SCRIPT_DIR="$TEST_WORK_DIR"
    _load_ensure_env_file

    ensure_env_file
    run diff "$TEST_WORK_DIR/.env" "$TEST_WORK_DIR/.env.example"
    assert_success
}

@test "ensure_env_file does nothing when .env already exists" {
    echo "EXISTING=true" > "$TEST_WORK_DIR/.env"
    printf 'POSTGRES_USER=ralph\n' > "$TEST_WORK_DIR/.env.example"

    SCRIPT_DIR="$TEST_WORK_DIR"
    _load_ensure_env_file

    run ensure_env_file
    assert_success
    refute_output --partial "Created .env"
    # Original content preserved
    run cat "$TEST_WORK_DIR/.env"
    assert_output "EXISTING=true"
}

@test "ensure_env_file warns when both .env and .env.example are missing" {
    # Neither .env nor .env.example exist in TEST_WORK_DIR
    SCRIPT_DIR="$TEST_WORK_DIR"
    _load_ensure_env_file

    run ensure_env_file
    assert_success
    assert_output --partial "Warning"
    assert_output --partial ".env.example"
    assert_file_not_exists "$TEST_WORK_DIR/.env"
}

@test "ensure_env_file does not exit on missing .env.example" {
    SCRIPT_DIR="$TEST_WORK_DIR"
    _load_ensure_env_file

    # Should return 0 (continue execution), not exit
    run ensure_env_file
    assert_success
}

# --- .env sourcing tests ---

# Helper: run the sourcing block extracted from ralph.sh
_source_env() {
    if [ -f "$SCRIPT_DIR/.env" ]; then
        _saved_db_url="${RALPH_DB_URL:-}"
        . "$SCRIPT_DIR/.env"
        if [ -n "$_saved_db_url" ]; then RALPH_DB_URL="$_saved_db_url"; fi
    fi
}

@test "sourcing .env sets RALPH_DB_URL when not already set" {
    printf 'RALPH_DB_URL=postgres://ralph:ralph@localhost:5432/ralph\n' > "$TEST_WORK_DIR/.env"
    unset RALPH_DB_URL
    SCRIPT_DIR="$TEST_WORK_DIR"
    _source_env
    [ "$RALPH_DB_URL" = "postgres://ralph:ralph@localhost:5432/ralph" ]
}

@test "sourcing .env sets POSTGRES_* vars" {
    printf 'POSTGRES_USER=ralph\nPOSTGRES_PASSWORD=ralph\nPOSTGRES_DB=ralph\nPOSTGRES_PORT=5432\nRALPH_DB_URL=postgres://ralph:ralph@localhost:5432/ralph\n' > "$TEST_WORK_DIR/.env"
    unset RALPH_DB_URL POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB POSTGRES_PORT
    SCRIPT_DIR="$TEST_WORK_DIR"
    _source_env
    [ "$POSTGRES_USER" = "ralph" ]
    [ "$POSTGRES_PASSWORD" = "ralph" ]
    [ "$POSTGRES_DB" = "ralph" ]
    [ "$POSTGRES_PORT" = "5432" ]
}

@test "sourcing .env preserves existing RALPH_DB_URL" {
    printf 'RALPH_DB_URL=postgres://ralph:ralph@localhost:5432/ralph\n' > "$TEST_WORK_DIR/.env"
    RALPH_DB_URL="postgres://custom:custom@remotehost:5432/mydb"
    SCRIPT_DIR="$TEST_WORK_DIR"
    _source_env
    [ "$RALPH_DB_URL" = "postgres://custom:custom@remotehost:5432/mydb" ]
}

@test "sourcing .env loads POSTGRES_* even when RALPH_DB_URL is pre-set" {
    printf 'POSTGRES_USER=ralph\nPOSTGRES_PORT=5432\nRALPH_DB_URL=postgres://ralph:ralph@localhost:5432/ralph\n' > "$TEST_WORK_DIR/.env"
    RALPH_DB_URL="postgres://custom:custom@remotehost:5432/mydb"
    unset POSTGRES_USER POSTGRES_PORT
    SCRIPT_DIR="$TEST_WORK_DIR"
    _source_env
    [ "$POSTGRES_USER" = "ralph" ]
    [ "$POSTGRES_PORT" = "5432" ]
    [ "$RALPH_DB_URL" = "postgres://custom:custom@remotehost:5432/mydb" ]
}
