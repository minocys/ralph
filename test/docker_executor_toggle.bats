#!/usr/bin/env bats
# test/docker_executor_toggle.bats — detect_docker_executor tests for lib/docker.sh

load test_helper

# Source lib/docker.sh to get detect_docker_executor
_source_docker_lib() {
    export SCRIPT_DIR="$SCRIPT_DIR"
    . "$SCRIPT_DIR/lib/docker.sh"
}

# --- default behavior (unset) ---

@test "detect_docker_executor sets RALPH_EXEC_MODE=local when DOCKER_EXECUTOR is unset" {
    _source_docker_lib
    unset DOCKER_EXECUTOR
    detect_docker_executor
    [ "$RALPH_EXEC_MODE" = "local" ]
}

@test "detect_docker_executor sets RALPH_EXEC_MODE=local when DOCKER_EXECUTOR is empty" {
    _source_docker_lib
    export DOCKER_EXECUTOR=""
    detect_docker_executor
    [ "$RALPH_EXEC_MODE" = "local" ]
}

# --- explicit false ---

@test "detect_docker_executor sets RALPH_EXEC_MODE=local when DOCKER_EXECUTOR=false" {
    _source_docker_lib
    export DOCKER_EXECUTOR="false"
    detect_docker_executor
    [ "$RALPH_EXEC_MODE" = "local" ]
}

@test "detect_docker_executor sets RALPH_EXEC_MODE=local when DOCKER_EXECUTOR=FALSE" {
    _source_docker_lib
    export DOCKER_EXECUTOR="FALSE"
    detect_docker_executor
    [ "$RALPH_EXEC_MODE" = "local" ]
}

# --- docker mode ---

@test "detect_docker_executor sets RALPH_EXEC_MODE=docker when DOCKER_EXECUTOR=true" {
    _source_docker_lib
    export DOCKER_EXECUTOR="true"
    detect_docker_executor
    [ "$RALPH_EXEC_MODE" = "docker" ]
}

@test "detect_docker_executor sets RALPH_EXEC_MODE=docker when DOCKER_EXECUTOR=TRUE" {
    _source_docker_lib
    export DOCKER_EXECUTOR="TRUE"
    detect_docker_executor
    [ "$RALPH_EXEC_MODE" = "docker" ]
}

@test "detect_docker_executor sets RALPH_EXEC_MODE=docker when DOCKER_EXECUTOR=True" {
    _source_docker_lib
    export DOCKER_EXECUTOR="True"
    detect_docker_executor
    [ "$RALPH_EXEC_MODE" = "docker" ]
}

# --- export ---

@test "detect_docker_executor exports RALPH_EXEC_MODE" {
    _source_docker_lib
    export DOCKER_EXECUTOR="true"
    detect_docker_executor
    # Verify it's exported by running a subshell
    run bash -c 'echo "$RALPH_EXEC_MODE"'
    assert_success
    assert_output "docker"
}

# --- return code ---

@test "detect_docker_executor returns 0 when DOCKER_EXECUTOR=true" {
    _source_docker_lib
    export DOCKER_EXECUTOR="true"
    run detect_docker_executor
    assert_success
}

@test "detect_docker_executor returns 0 when DOCKER_EXECUTOR is unset" {
    _source_docker_lib
    unset DOCKER_EXECUTOR
    run detect_docker_executor
    assert_success
}

# --- non-true values ---

@test "detect_docker_executor sets local for non-true values" {
    _source_docker_lib
    export DOCKER_EXECUTOR="yes"
    detect_docker_executor
    [ "$RALPH_EXEC_MODE" = "local" ]
}

@test "detect_docker_executor sets local for numeric 1" {
    _source_docker_lib
    export DOCKER_EXECUTOR="1"
    detect_docker_executor
    [ "$RALPH_EXEC_MODE" = "local" ]
}
