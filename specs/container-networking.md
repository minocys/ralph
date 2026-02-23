# Container Networking & Compose

## Overview

The `ralph-worker` container must communicate with the existing `ralph-task-db` PostgreSQL container over a shared Docker network. This spec defines the network configuration and the additions to `docker-compose.yml` that connect the worker service to the database service while preserving host-side access.

## Requirements

- A named Docker network `ralph-net` is defined in `docker-compose.yml` with the default bridge driver.
- Both `ralph-task-db` and `ralph-worker` services are attached to `ralph-net`.
- Inside the `ralph-net` network, the worker connects to PostgreSQL using the service name as hostname: `ralph-task-db:5432` (the internal PostgreSQL port, not the host-mapped 5499).
- The host machine continues to access PostgreSQL via `localhost:5499` (the existing port mapping is unchanged).
- When `DOCKER_EXECUTOR=true`, the `RALPH_DB_URL` passed to the worker container uses the internal network address: `postgres://ralph:ralph@ralph-task-db:5432/ralph`.
- When `DOCKER_EXECUTOR=false` (local mode), `RALPH_DB_URL` continues to use `localhost:5499` as today.
- The `ralph-worker` service in `docker-compose.yml` declares `depends_on: ralph-task-db` with a `condition: service_healthy` to ensure the database is ready before the worker starts.
- The `ralph-task-db` service definition is unchanged apart from being added to the `ralph-net` network.

## Constraints

- The network must be defined in the same `docker-compose.yml` file (no external network creation required).
- Host networking mode (`--network=host`) is not used because it is unreliable on Docker Desktop for macOS.
- The `ralph-task-db` port mapping (`5499:5432`) must remain so host tools (e.g., `psql` from the host, `task` CLI run locally) continue to work.

## Out of Scope

- TLS or encrypted connections between worker and database.
- Network policies or firewall rules.
- Multi-host networking (Docker Swarm overlay, Kubernetes services).
- Load balancing across multiple worker containers.
