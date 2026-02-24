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
