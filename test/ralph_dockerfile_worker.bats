#!/usr/bin/env bats
# test/ralph_dockerfile_worker.bats — Dockerfile.worker content validation

load test_helper

@test "Dockerfile.worker exists in repo root" {
    assert_file_exist "$SCRIPT_DIR/Dockerfile.worker"
}

@test "Dockerfile.worker uses node:20-alpine as base image" {
    run grep -E '^FROM node:20-alpine' "$SCRIPT_DIR/Dockerfile.worker"
    assert_success
}

@test "Dockerfile.worker installs bash via apk" {
    run grep -E 'apk add.*bash' "$SCRIPT_DIR/Dockerfile.worker"
    assert_success
}

@test "Dockerfile.worker installs git via apk" {
    run grep -E 'apk add.*git' "$SCRIPT_DIR/Dockerfile.worker"
    assert_success
}

@test "Dockerfile.worker installs jq via apk" {
    run grep -E 'apk add.*jq' "$SCRIPT_DIR/Dockerfile.worker"
    assert_success
}

@test "Dockerfile.worker installs postgresql-client via apk" {
    run grep -E 'apk add.*postgresql-client' "$SCRIPT_DIR/Dockerfile.worker"
    assert_success
}

@test "Dockerfile.worker uses --no-cache flag for apk" {
    run grep -E 'apk add --no-cache' "$SCRIPT_DIR/Dockerfile.worker"
    assert_success
}

@test "Dockerfile.worker installs claude-code globally via npm" {
    run grep -E 'npm install -g @anthropic-ai/claude-code' "$SCRIPT_DIR/Dockerfile.worker"
    assert_success
}

@test "Dockerfile.worker installs claude-code before creating non-root user" {
    local npm_line
    local adduser_line
    npm_line=$(grep -n 'npm install -g @anthropic-ai/claude-code' "$SCRIPT_DIR/Dockerfile.worker" | head -1 | cut -d: -f1)
    adduser_line=$(grep -n 'adduser -D -u 1000 ralph' "$SCRIPT_DIR/Dockerfile.worker" | head -1 | cut -d: -f1)
    [ "$npm_line" -lt "$adduser_line" ]
}

@test "Dockerfile.worker creates non-root ralph user with UID 1000" {
    run grep -E 'adduser -D -u 1000 ralph' "$SCRIPT_DIR/Dockerfile.worker"
    assert_success
}

@test "Dockerfile.worker creates /workspace directory owned by ralph" {
    run grep -E 'mkdir -p /workspace.*chown ralph:ralph /workspace' "$SCRIPT_DIR/Dockerfile.worker"
    assert_success
}

@test "Dockerfile.worker sets WORKDIR to /workspace" {
    run grep -E '^WORKDIR /workspace' "$SCRIPT_DIR/Dockerfile.worker"
    assert_success
}
