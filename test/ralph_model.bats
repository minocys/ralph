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

@test "--model opus-4.5 resolves to anthropic ID" {
    mock_settings_json
    run "$SCRIPT_DIR/ralph.sh" --model opus-4.5 -n 1
    assert_success
    assert_output --partial "Model:  opus-4.5 (claude-opus-4-5-20251101)"
}

@test "--model opus-4.5 resolves to bedrock ID" {
    mock_settings_json bedrock
    run "$SCRIPT_DIR/ralph.sh" --model opus-4.5 -n 1
    assert_success
    assert_output --partial "Model:  opus-4.5 (global.anthropic.claude-opus-4-5-20251101-v1:0)"
}

@test "unknown alias passes through as model ID" {
    mock_settings_json
    run "$SCRIPT_DIR/ralph.sh" --model nonexistent -n 1
    assert_success
    assert_output --partial "Model:  nonexistent (nonexistent)"
}

@test "no --model flag omits --model from claude args" {
    mock_settings_json
    run "$SCRIPT_DIR/ralph.sh" -n 1
    assert_success
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
    run "$SCRIPT_DIR/ralph.sh" -m opus-4.5 -n 1
    assert_success
    assert_output --partial "Model:  opus-4.5 (claude-opus-4-5-20251101)"
}

@test "full model ID passes through unchanged" {
    mock_settings_json
    run "$SCRIPT_DIR/ralph.sh" --model claude-opus-4-5-20251101 -n 1
    assert_success
    assert_output --partial "Model:  claude-opus-4-5-20251101 (claude-opus-4-5-20251101)"
}

@test "arbitrary string passes through as model ID" {
    mock_settings_json
    run "$SCRIPT_DIR/ralph.sh" --model my-custom-model -n 1
    assert_success
    assert_output --partial "Model:  my-custom-model (my-custom-model)"
}

@test "environment variable CLAUDE_CODE_USE_BEDROCK=1 selects bedrock" {
    mock_settings_json
    export CLAUDE_CODE_USE_BEDROCK=1
    run "$SCRIPT_DIR/ralph.sh" -n 1
    assert_success
    assert_output --partial "Backend: bedrock"
    unset CLAUDE_CODE_USE_BEDROCK
}
