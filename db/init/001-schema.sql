-- Ralph task management schema
-- Extracted from task script ensure_schema() for Docker entrypoint initialization.
-- Uses CREATE TABLE IF NOT EXISTS for idempotency.

SET client_min_messages TO WARNING;

CREATE TABLE IF NOT EXISTS tasks (
    id              TEXT PRIMARY KEY,
    title           TEXT NOT NULL,
    description     TEXT,
    category        TEXT,
    priority        INT DEFAULT 2,
    status          TEXT DEFAULT 'open',
    spec_ref        TEXT,
    ref             TEXT,
    result          JSONB,
    assignee        TEXT,
    lease_expires_at TIMESTAMPTZ,
    retry_count     INT DEFAULT 0,
    fail_reason     TEXT,
    steps           TEXT[],
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ,
    deleted_at      TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS task_deps (
    task_id    TEXT REFERENCES tasks(id) ON DELETE CASCADE,
    blocked_by TEXT REFERENCES tasks(id) ON DELETE CASCADE,
    PRIMARY KEY (task_id, blocked_by)
);

CREATE TABLE IF NOT EXISTS agents (
    id         TEXT PRIMARY KEY,
    pid        INT,
    hostname   TEXT,
    started_at TIMESTAMPTZ DEFAULT now(),
    status     TEXT DEFAULT 'active'
);
