#!/usr/bin/env bats
load test_helper

# ---------------------------------------------------------------------------
# generate_uuid – produces RFC-4122-shaped lowercase hex UUIDs
# ---------------------------------------------------------------------------

# Evaluate generate_uuid from lib/task without running main.
_call_generate_uuid() {
    eval "$(sed -n '/^generate_uuid()/,/^}/p' "$SCRIPT_DIR/lib/task")"
    generate_uuid
}

@test "generate_uuid output matches UUID pattern [0-9a-f-]{36}" {
    run _call_generate_uuid
    assert_success
    [[ "${#output}" -eq 36 ]]
    [[ "$output" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]
}

@test "generate_uuid output is lowercase" {
    run _call_generate_uuid
    assert_success
    # Ensure no uppercase characters exist
    [[ "$output" == "$(printf '%s' "$output" | tr '[:upper:]' '[:lower:]')" ]]
}

@test "successive generate_uuid calls produce different values" {
    run _call_generate_uuid
    assert_success
    local uuid1="$output"

    run _call_generate_uuid
    assert_success
    local uuid2="$output"

    [[ "$uuid1" != "$uuid2" ]]
}
