#!/usr/bin/env bats
# test/ralph_model.bats — model & backend resolution tests for ralph.sh

load test_helper

# Helper: set up a fake ~/.claude/settings.json for backend detection
# Usage: mock_settings_json [bedrock]
# With no args: anthropic backend (no bedrock flag)
# With "bedrock": sets CLAUDE_CODE_USE_BEDROCK to "1"
mock_settings_json() {
    local fake_home="$TEST_WORK_DIR/fakehome"
    mkdir -p "$fake_home/.claude"
    if [ "${1:-}" = "bedrock" ]; then
        cat > "$fake_home/.claude/settings.json" <<'EOF'
{"env":{"CLAUDE_CODE_USE_BEDROCK":"1"}}
EOF
    else
        cat > "$fake_home/.claude/settings.json" <<'EOF'
{"env":{}}
EOF
    fi
    export HOME="$fake_home"
}

@test "--model opus resolves to anthropic ID" {
    mock_settings_json
    run "$SCRIPT_DIR/ralph.sh" --model opus -n 1
    assert_success
    assert_output --partial "Model:  opus (claude-opus-4-20250514)"
}

@test "--model opus resolves to bedrock ID" {
    mock_settings_json bedrock
    run "$SCRIPT_DIR/ralph.sh" --model opus -n 1
    assert_success
    assert_output --partial "Model:  opus (us.anthropic.claude-opus-4-20250514-v1:0)"
}

@test "invalid alias exits 1 with available list" {
    mock_settings_json
    run "$SCRIPT_DIR/ralph.sh" --model nonexistent -n 1
    assert_failure
    assert_output --partial "Unknown model alias 'nonexistent'"
    assert_output --partial "opus"
    assert_output --partial "sonnet"
    assert_output --partial "haiku"
}

@test "no --model flag omits --model from claude args" {
    mock_settings_json
    run "$SCRIPT_DIR/ralph.sh" -n 1
    assert_success
    refute_output --partial "ARGS: .*--model"
    # The stub prints ARGS: ..., verify --model is not in it
    refute_line --partial "--model"
}

@test "--model with each alias in models.json succeeds" {
    mock_settings_json
    local aliases
    aliases=$(jq -r 'keys[]' "$SCRIPT_DIR/models.json")
    for alias in $aliases; do
        run "$SCRIPT_DIR/ralph.sh" --model "$alias" -n 1
        assert_success
        assert_output --partial "Model:  $alias ("
    done
}

@test "-m is an alias for --model" {
    mock_settings_json
    run "$SCRIPT_DIR/ralph.sh" -m opus -n 1
    assert_success
    assert_output --partial "Model:  opus (claude-opus-4-20250514)"
}
