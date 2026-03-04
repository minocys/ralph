#!/usr/bin/env bats
# test/task_build_steps.bats — verify build_steps_literal() produces correct
# SQL-safe JSON array strings for SQLite storage.

load test_helper

# ---------------------------------------------------------------------------
# Extract build_steps_literal + dependencies from lib/task
# ---------------------------------------------------------------------------
_source_funcs() {
    eval "$(sed -n '/^sql_esc()/,/^}/p' "$SCRIPT_DIR/lib/task")"
    eval "$(sed -n '/^build_steps_literal()/,/^}/p' "$SCRIPT_DIR/lib/task")"
}

setup() {
    _source_funcs
}

# ---------------------------------------------------------------------------
# Empty / null input → NULL
# ---------------------------------------------------------------------------
@test "build_steps_literal: empty array returns NULL" {
    run build_steps_literal '[]'
    assert_success
    assert_output "NULL"
}

@test "build_steps_literal: null input returns NULL" {
    run build_steps_literal 'null'
    assert_success
    assert_output "NULL"
}

@test "build_steps_literal: empty string returns NULL" {
    run build_steps_literal ''
    assert_success
    assert_output "NULL"
}

# ---------------------------------------------------------------------------
# Single step
# ---------------------------------------------------------------------------
@test "build_steps_literal: single step returns SQL-quoted JSON array" {
    run build_steps_literal '["step1"]'
    assert_success
    assert_output ''"'"'["step1"]'"'"''
}

# ---------------------------------------------------------------------------
# Multiple steps
# ---------------------------------------------------------------------------
@test "build_steps_literal: multi-step returns valid JSON array" {
    run build_steps_literal '["step1","step2","step3"]'
    assert_success
    assert_output ''"'"'["step1","step2","step3"]'"'"''
}

# ---------------------------------------------------------------------------
# Special characters
# ---------------------------------------------------------------------------
@test "build_steps_literal: step with single quotes is SQL-escaped" {
    run build_steps_literal '["it'"'"'s a test"]'
    assert_success
    # Inner single quote gets doubled for SQL escaping, wrapped in outer quotes
    assert_output "'[\"it''s a test\"]'"
}

@test "build_steps_literal: step with double quotes is preserved" {
    run build_steps_literal '["say \"hello\""]'
    assert_success
    # jq -c preserves escaped double quotes inside the JSON string
    assert_output ''"'"'["say \"hello\""]'"'"''
}

@test "build_steps_literal: step with newlines is compacted" {
    local input
    input=$(printf '[\n  "step one",\n  "step two"\n]')
    run build_steps_literal "$input"
    assert_success
    assert_output ''"'"'["step one","step two"]'"'"''
}

# ---------------------------------------------------------------------------
# Output is valid JSON inside SQL quotes
# ---------------------------------------------------------------------------
@test "build_steps_literal: output inner content is valid JSON" {
    run build_steps_literal '["a","b","c"]'
    assert_success
    # Strip surrounding SQL single quotes and validate as JSON
    local inner="${output:1:${#output}-2}"
    run jq -e '.' <<< "$inner"
    assert_success
}

@test "build_steps_literal: multi-step output parses to correct array length" {
    run build_steps_literal '["x","y","z"]'
    assert_success
    local inner="${output:1:${#output}-2}"
    run jq 'length' <<< "$inner"
    assert_success
    assert_output "3"
}
