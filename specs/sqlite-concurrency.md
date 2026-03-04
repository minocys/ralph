# SQLite Concurrency

Replace PostgreSQL's row-level locking (`FOR UPDATE SKIP LOCKED`) with SQLite's WAL mode and serialized write transactions for concurrent task claiming.

## Overview

PostgreSQL's `SELECT ... FOR UPDATE SKIP LOCKED` is the current mechanism that prevents two build agents from claiming the same task. SQLite has no row-level locking — it uses file-level locking with a single-writer model. This spec defines the replacement concurrency strategy using WAL mode, `BEGIN IMMEDIATE` transactions, and retry-on-busy logic. The target workload is 1-4 concurrent build agents on a single machine.

## Requirements

### WAL Mode

- Every `sqlite3` connection must set `PRAGMA journal_mode=WAL` before any read or write operation
- WAL mode allows concurrent readers while a single writer holds the lock, which is sufficient for Ralph's read-heavy peek / write-rare claim pattern
- WAL mode is persistent — once set, it remains across connections until explicitly changed

### Write Serialization for Claims

- All claim operations (`ralph task claim`) must use `BEGIN IMMEDIATE` instead of `BEGIN` (plain)
- `BEGIN IMMEDIATE` acquires a write lock at transaction start, preventing two concurrent claim transactions from interleaving
- The claim transaction must:
  1. `BEGIN IMMEDIATE`
  2. SELECT the eligible task (open + unblocked, or active with expired lease), ordered by priority ASC, created_at ASC, `LIMIT 1`
  3. UPDATE the selected task: set status to `active`, assignee, `lease_expires_at`, increment `retry_count` if reclaiming
  4. SELECT the updated task row plus blocker results
  5. `COMMIT`
- If no eligible task is found in step 2, `ROLLBACK` and exit code 2
- For targeted claims (`ralph task claim <id>`), step 2 selects the specific task by slug and verifies eligibility within the same transaction

### Retry on SQLITE_BUSY

- When `sqlite3` returns error code 5 (SQLITE_BUSY), the operation must be retried
- `PRAGMA busy_timeout=5000` is the first line of defense — SQLite will internally retry for up to 5 seconds before returning BUSY
- If a BUSY error still occurs after the pragma timeout (e.g., under heavy contention), the script retries the entire transaction up to 3 times with exponential backoff: 100ms, 300ms, 900ms
- Retry logic is implemented as a wrapper function (e.g., `sql_write()`) used by all write operations, not just claims
- Total maximum wait: 5s (pragma) + 1.3s (retries) = ~6.3s — acceptable for 1-4 agents

### Other Write Operations

- `ralph task plan-sync` must also use `BEGIN IMMEDIATE` for its multi-statement transaction (it already uses a single transaction in PostgreSQL)
- `ralph task done`, `ralph task fail`, `ralph task renew`, `ralph task create`, `ralph task update`, `ralph task delete` must use `BEGIN IMMEDIATE` for their write transactions
- `ralph task agent register` and `ralph task agent deregister` must use `BEGIN IMMEDIATE`
- Read-only operations (`ralph task peek`, `ralph task list`, `ralph task show`, `ralph task deps`) use plain `BEGIN` (or no explicit transaction — SQLite auto-wraps single SELECTs)

### Atomicity Guarantee

- The claim must still be atomic: no two concurrent agents can claim the same task
- With `BEGIN IMMEDIATE`, only one writer can proceed at a time — the second writer either waits (busy_timeout) or gets SQLITE_BUSY
- Since the entire SELECT + UPDATE happens within a single `BEGIN IMMEDIATE` transaction, no race condition exists between reading the eligible task and updating it
- This replaces the PostgreSQL guarantee: `FOR UPDATE SKIP LOCKED` → `BEGIN IMMEDIATE` with serialized access

## Constraints

- Maximum concurrent writers: effectively 1 at a time (SQLite's design); contention is handled by busy_timeout and retry
- The `PRAGMA busy_timeout` value of 5000ms is chosen to exceed the expected duration of any single write transaction (typically <100ms for a claim, <500ms for plan-sync)
- All PRAGMAs (`journal_mode`, `foreign_keys`, `busy_timeout`) must be set on every connection because SQLite does not persist session-level PRAGMAs across connections (except `journal_mode` which is persistent)
- The retry wrapper must re-execute the entire transaction, not resume from the failed statement

## Out of Scope

- Multi-machine concurrent access (SQLite is designed for single-machine use; network filesystems are unreliable with SQLite locking)
- Read replicas or write-ahead log shipping
- Advisory file locking (flock) — the built-in SQLite locking is sufficient for the target workload
- Connection pooling or persistent connections
