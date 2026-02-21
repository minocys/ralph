# DoltgreSQL Migration

Replace PostgreSQL with DoltgreSQL as the task database backend to enable git-like version control (branching, committing, diffing) on task data.

## Requirements

### Docker Compose

- Replace the `postgres:17-alpine` image with `dolthub/doltgresql:latest`
- The DoltgreSQL container must expose port 5432 and accept standard PostgreSQL wire protocol connections
- Environment variables for the container must use `DOLTGRES_USER` and `DOLTGRES_PASSWORD` (aliased from `POSTGRES_USER` and `POSTGRES_PASSWORD`)
- The data volume mount must point to `/var/lib/doltgresql/` inside the container

### Connection String

- `RALPH_DB_URL` format is unchanged: `postgres://user:pass@host:5432/dbname`
- DoltgreSQL accepts standard PostgreSQL connection strings on the wire protocol
- The `.env` / `.env.example` files do not need format changes

### Schema Compatibility

- `ensure_schema()` must work against DoltgreSQL using the same `CREATE TABLE IF NOT EXISTS` statements
- All column types used in the current schema (`TEXT`, `INT`, `TIMESTAMPTZ`, `JSONB`) must be supported by DoltgreSQL
- Primary keys, foreign keys with `ON DELETE CASCADE`, and `DEFAULT` expressions must behave identically

### SQL Compatibility

- `SELECT FOR UPDATE SKIP LOCKED` must work for the `claim` command's atomic claiming pattern
- `BEGIN` / `COMMIT` transaction blocks must work for `plan-sync` and `create`
- `INSERT ... ON CONFLICT DO NOTHING` must work for `agent register` and `block`
- `json_build_object()`, `json_agg()`, `json_object_agg()`, and `COALESCE` on JSON types must produce correct output
- Recursive CTEs (`WITH RECURSIVE`) must work for the `deps` command
- `interval` expressions (`now() + interval 'N seconds'`) must work for lease management
- `psql` CLI flags `-tAX` must produce the same pipe-delimited, tuples-only output

### Validation

- All existing tests in `tests/` must pass against DoltgreSQL without modification
- If any SQL feature is unsupported, document it and provide a workaround before proceeding with the migration

## Constraints

- DoltgreSQL is in Beta (since April 2025) — the project accepts this tradeoff for native branching capability
- DoltgreSQL is ~3-7x slower than PostgreSQL on benchmarks; this is acceptable for the task CLI's workload (infrequent, small queries)
- DoltgreSQL is not running the actual PostgreSQL binary — it is a separate engine that speaks the PostgreSQL wire protocol and parses PostgreSQL SQL dialect
- No ORM or connection pooling — each `psql` invocation opens and closes a connection, same as before

## Out of Scope

- Migrating existing task data from PostgreSQL to DoltgreSQL (tasks are ephemeral per planning cycle)
- Using DoltgreSQL remotes (push/pull to DoltHub)
- Using DoltgreSQL's merge, diff, or history features (covered by the task-branch-scoping spec)
- Performance optimization or benchmarking beyond basic validation
