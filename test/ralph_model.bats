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

@test "--model opus-4.5 passes through on anthropic backend" {
    mock_settings_json
    run "$SCRIPT_DIR/ralph.sh" --model opus-4.5 -n 1
    assert_success
    assert_output --partial "Model:  opus-4.5 (opus-4.5)"
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
    assert_output --partial "Model:  opus-4.5 (opus-4.5)"
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

@test "inline env var takes precedence over all settings files" {
    # Set up conflicting settings files (all set to anthropic/empty)
    local fake_home="$TEST_WORK_DIR/fakehome"
    mkdir -p "$fake_home/.claude"
    cat > "$fake_home/.claude/settings.json" <<'EOF'
{"env":{}}
EOF
    export HOME="$fake_home"

    # Create project-level settings files also without bedrock flag
    mkdir -p "$TEST_WORK_DIR/.claude"
    cat > "$TEST_WORK_DIR/.claude/settings.json" <<'EOF'
{"env":{}}
EOF
    cat > "$TEST_WORK_DIR/.claude/settings.local.json" <<'EOF'
{"env":{}}
EOF

    # Run with inline env var set to bedrock - should override all settings files
    CLAUDE_CODE_USE_BEDROCK=1 run "$SCRIPT_DIR/ralph.sh" -n 1
    assert_success
    assert_output --partial "Backend: bedrock"
}

@test "./.claude/settings.local.json takes precedence over ./.claude/settings.json" {
    # Set up fake home with anthropic settings
    local fake_home="$TEST_WORK_DIR/fakehome"
    mkdir -p "$fake_home/.claude"
    cat > "$fake_home/.claude/settings.json" <<'EOF'
{"env":{}}
EOF
    export HOME="$fake_home"

    # Create project-level settings files with conflicting backends
    mkdir -p "$TEST_WORK_DIR/.claude"

    # settings.json has anthropic (no bedrock flag)
    cat > "$TEST_WORK_DIR/.claude/settings.json" <<'EOF'
{"env":{}}
EOF

    # settings.local.json has bedrock - should win
    cat > "$TEST_WORK_DIR/.claude/settings.local.json" <<'EOF'
{"env":{"CLAUDE_CODE_USE_BEDROCK":"1"}}
EOF

    # Ensure no environment variable is set
    unset CLAUDE_CODE_USE_BEDROCK

    # Run ralph.sh - settings.local.json should take precedence
    run "$SCRIPT_DIR/ralph.sh" -n 1
    assert_success
    assert_output --partial "Backend: bedrock"
}

@test "./.claude/settings.json takes precedence over ~/.claude/settings.json" {
    # Set up fake home with bedrock settings (lowest priority)
    local fake_home="$TEST_WORK_DIR/fakehome"
    mkdir -p "$fake_home/.claude"
    cat > "$fake_home/.claude/settings.json" <<'EOF'
{"env":{}}
EOF
    export HOME="$fake_home"

    # Create project-level settings.json with bedrock - should win over user settings
    mkdir -p "$TEST_WORK_DIR/.claude"
    cat > "$TEST_WORK_DIR/.claude/settings.json" <<'EOF'
{"env":{"CLAUDE_CODE_USE_BEDROCK":"1"}}
EOF

    # Ensure no environment variable or settings.local.json exists
    unset CLAUDE_CODE_USE_BEDROCK

    # Run ralph.sh - project-level settings.json should take precedence
    run "$SCRIPT_DIR/ralph.sh" -n 1
    assert_success
    assert_output --partial "Backend: bedrock"
}

@test "backend banner shows anthropic when bedrock is not configured" {
    mock_settings_json
    run "$SCRIPT_DIR/ralph.sh" -n 1
    assert_success
    assert_output --partial "Backend: anthropic"
}

@test "backend banner shows bedrock when bedrock is configured" {
    mock_settings_json bedrock
    run "$SCRIPT_DIR/ralph.sh" -n 1
    assert_success
    assert_output --partial "Backend: bedrock"
}

@test "CLAUDE_CODE_USE_BEDROCK=0 with bedrock settings files still uses anthropic" {
    # Set up settings files that would select bedrock
    local fake_home="$TEST_WORK_DIR/fakehome"
    mkdir -p "$fake_home/.claude"
    cat > "$fake_home/.claude/settings.json" <<'EOF'
{"env":{"CLAUDE_CODE_USE_BEDROCK":"1"}}
EOF
    export HOME="$fake_home"

    mkdir -p "$TEST_WORK_DIR/.claude"
    cat > "$TEST_WORK_DIR/.claude/settings.json" <<'EOF'
{"env":{"CLAUDE_CODE_USE_BEDROCK":"1"}}
EOF
    cat > "$TEST_WORK_DIR/.claude/settings.local.json" <<'EOF'
{"env":{"CLAUDE_CODE_USE_BEDROCK":"1"}}
EOF

    # Run with CLAUDE_CODE_USE_BEDROCK=0 as inline env var
    # The env var should take precedence even when value is '0'
    CLAUDE_CODE_USE_BEDROCK=0 run "$SCRIPT_DIR/ralph.sh" -n 1
    assert_success
    assert_output --partial "Backend: anthropic"
}
