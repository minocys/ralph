#!/usr/bin/env bats
# test/task_render_md.bats — Tests for the render_task_md helper function

load test_helper

# ---------------------------------------------------------------------------
# render_task_md: basic rendering
# ---------------------------------------------------------------------------

@test "render_task_md renders task header and id" {
    run "$SCRIPT_DIR/task" _render-md '{"id":"test/01","t":"My task","p":0,"s":"open","cat":null,"spec":null,"ref":null,"assignee":null,"deps":[],"steps":[]}'
    assert_success
    assert_line --index 0 "## Task test/01"
    assert_line --index 1 "id: test/01"
}

@test "render_task_md renders core fields" {
    run "$SCRIPT_DIR/task" _render-md '{"id":"test/02","t":"Build CLI","p":1,"s":"active","cat":"feat","spec":"task-cli.md","ref":null,"assignee":"a7f2","deps":[],"steps":[]}'
    assert_success
    assert_output --partial "## Task test/02"
    assert_output --partial "id: test/02"
    assert_output --partial "title: Build CLI"
    assert_output --partial "priority: 1"
    assert_output --partial "status: active"
    assert_output --partial "category: feat"
    assert_output --partial "spec: task-cli.md"
    assert_output --partial "assignee: a7f2"
}

@test "render_task_md omits null fields" {
    run "$SCRIPT_DIR/task" _render-md '{"id":"test/03","t":"Minimal","p":2,"s":"open","cat":null,"spec":null,"ref":null,"assignee":null,"deps":[],"steps":[]}'
    assert_success
    assert_output --partial "## Task test/03"
    assert_output --partial "title: Minimal"
    assert_output --partial "priority: 2"
    assert_output --partial "status: open"
    refute_output --partial "category:"
    refute_output --partial "spec:"
    refute_output --partial "ref:"
    refute_output --partial "assignee:"
    refute_output --partial "deps:"
    refute_output --partial "steps:"
}

@test "render_task_md renders priority 0 (not omitted)" {
    run "$SCRIPT_DIR/task" _render-md '{"id":"test/04","t":"Critical","p":0,"s":"open","cat":null,"spec":null,"ref":null,"assignee":null,"deps":[],"steps":[]}'
    assert_success
    assert_output --partial "priority: 0"
}

@test "render_task_md renders deps as comma-separated list" {
    run "$SCRIPT_DIR/task" _render-md '{"id":"test/05","t":"With deps","p":0,"s":"open","cat":null,"spec":null,"ref":null,"assignee":null,"deps":["dep/01","dep/02","dep/03"],"steps":[]}'
    assert_success
    assert_output --partial "deps: dep/01, dep/02, dep/03"
}

@test "render_task_md renders single dep without comma" {
    run "$SCRIPT_DIR/task" _render-md '{"id":"test/06","t":"One dep","p":0,"s":"open","cat":null,"spec":null,"ref":null,"assignee":null,"deps":["blocker/01"],"steps":[]}'
    assert_success
    assert_output --partial "deps: blocker/01"
    # No trailing comma
    refute_output --partial "deps: blocker/01,"
}

@test "render_task_md renders steps as markdown bullet list" {
    run "$SCRIPT_DIR/task" _render-md '{"id":"test/07","t":"With steps","p":0,"s":"open","cat":null,"spec":null,"ref":null,"assignee":null,"deps":[],"steps":["Set up parsing","Add help text","Connect to DB"]}'
    assert_success
    assert_output --partial "steps:"
    assert_output --partial "- Set up parsing"
    assert_output --partial "- Add help text"
    assert_output --partial "- Connect to DB"
}

@test "render_task_md renders all fields together" {
    run "$SCRIPT_DIR/task" _render-md '{"id":"full/01","t":"Full task","p":0,"s":"active","cat":"feat","spec":"test.md","ref":"PR#42","assignee":"a7f2","deps":["dep/01","dep/02"],"steps":["Do thing","Do other thing"]}'
    assert_success
    assert_line --index 0  "## Task full/01"
    assert_line --index 1  "id: full/01"
    assert_line --index 2  "title: Full task"
    assert_line --index 3  "priority: 0"
    assert_line --index 4  "status: active"
    assert_line --index 5  "category: feat"
    assert_line --index 6  "spec: test.md"
    assert_line --index 7  "ref: PR#42"
    assert_line --index 8  "assignee: a7f2"
    assert_line --index 9  "deps: dep/01, dep/02"
    assert_line --index 10 "steps:"
    assert_line --index 11 "- Do thing"
    assert_line --index 12 "- Do other thing"
}

@test "render_task_md omits empty deps array" {
    run "$SCRIPT_DIR/task" _render-md '{"id":"test/08","t":"No deps","p":0,"s":"open","cat":null,"spec":null,"ref":null,"assignee":null,"deps":[],"steps":[]}'
    assert_success
    refute_output --partial "deps:"
}

@test "render_task_md omits empty steps array" {
    run "$SCRIPT_DIR/task" _render-md '{"id":"test/09","t":"No steps","p":0,"s":"open","cat":null,"spec":null,"ref":null,"assignee":null,"deps":[],"steps":[]}'
    assert_success
    refute_output --partial "steps:"
}

@test "render_task_md renders ref field when present" {
    run "$SCRIPT_DIR/task" _render-md '{"id":"test/10","t":"Has ref","p":0,"s":"open","cat":null,"spec":null,"ref":"[\"task\",\"test.bats\"]","assignee":null,"deps":[],"steps":[]}'
    assert_success
    assert_output --partial 'ref: ["task","test.bats"]'
}
