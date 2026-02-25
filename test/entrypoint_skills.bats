#!/usr/bin/env bats
# test/entrypoint_skills.bats — skill symlink tests for docker/entrypoint.sh

load test_helper

# Helper: run the skill symlink section from entrypoint.sh in a subshell.
# Uses _TEST_RALPH_DIR as RALPH_DIR.
_run_skill_symlinks() {
    local script
    script=$(cat <<'SCRIPT'
set -euo pipefail
RALPH_DIR="$_TEST_RALPH_DIR"
HOME="$_TEST_HOME"

mkdir -p ~/.claude/skills/
_skill_count=0
for skill_dir in "$RALPH_DIR"/skills/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name="$(basename "$skill_dir")"
    ln -sfn "$skill_dir" ~/.claude/skills/"$skill_name"
    _skill_count=$((_skill_count + 1))
done
echo "entrypoint: linked $_skill_count skill(s) into ~/.claude/skills/" >&2
SCRIPT
)
    run bash -c "$script"
}

setup() {
    TEST_WORK_DIR="$(mktemp -d)"
    export TEST_WORK_DIR

    # Fake RALPH_DIR with skills
    export _TEST_RALPH_DIR="$TEST_WORK_DIR/ralph"
    mkdir -p "$_TEST_RALPH_DIR/skills"

    # Fake HOME so we don't touch the real ~/.claude
    export _TEST_HOME="$TEST_WORK_DIR/home"
    mkdir -p "$_TEST_HOME"
}

teardown() {
    if [[ -d "$TEST_WORK_DIR" ]]; then
        rm -rf "$TEST_WORK_DIR"
    fi
}

# --- basic symlinking ---

@test "entrypoint creates ~/.claude/skills/ directory" {
    _run_skill_symlinks
    assert_success
    assert [ -d "$_TEST_HOME/.claude/skills" ]
}

@test "entrypoint symlinks skill directories into ~/.claude/skills/" {
    mkdir -p "$_TEST_RALPH_DIR/skills/ralph-build"
    echo "# build skill" > "$_TEST_RALPH_DIR/skills/ralph-build/SKILL.md"
    mkdir -p "$_TEST_RALPH_DIR/skills/ralph-plan"
    echo "# plan skill" > "$_TEST_RALPH_DIR/skills/ralph-plan/SKILL.md"

    _run_skill_symlinks
    assert_success
    assert [ -L "$_TEST_HOME/.claude/skills/ralph-build" ]
    assert [ -L "$_TEST_HOME/.claude/skills/ralph-plan" ]
}

@test "entrypoint logs skill symlink count to stderr" {
    mkdir -p "$_TEST_RALPH_DIR/skills/ralph-build"
    mkdir -p "$_TEST_RALPH_DIR/skills/ralph-plan"
    mkdir -p "$_TEST_RALPH_DIR/skills/ralph-spec"

    _run_skill_symlinks
    assert_success
    assert_output --partial "linked 3 skill(s)"
}

@test "entrypoint logs zero skills when skills directory is empty" {
    _run_skill_symlinks
    assert_success
    assert_output --partial "linked 0 skill(s)"
}

# --- idempotency ---

@test "entrypoint skill symlinks are idempotent" {
    mkdir -p "$_TEST_RALPH_DIR/skills/ralph-build"

    _run_skill_symlinks
    assert_success
    assert [ -L "$_TEST_HOME/.claude/skills/ralph-build" ]

    # Run again — must not fail
    _run_skill_symlinks
    assert_success
    assert [ -L "$_TEST_HOME/.claude/skills/ralph-build" ]
}

@test "entrypoint uses ln -sf to overwrite existing symlinks" {
    mkdir -p "$_TEST_RALPH_DIR/skills/ralph-build"

    # Create an initial symlink pointing elsewhere
    mkdir -p "$_TEST_HOME/.claude/skills"
    ln -s /tmp "$_TEST_HOME/.claude/skills/ralph-build"

    _run_skill_symlinks
    assert_success

    # Symlink should now point to the ralph skills dir
    local target
    target=$(readlink "$_TEST_HOME/.claude/skills/ralph-build")
    [[ "$target" == *"ralph/skills/ralph-build"* ]]
}

# --- edge cases ---

@test "entrypoint handles no skills directory gracefully" {
    rmdir "$_TEST_RALPH_DIR/skills"

    _run_skill_symlinks
    assert_success
    assert_output --partial "linked 0 skill(s)"
}
