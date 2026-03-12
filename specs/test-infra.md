# Test Infrastructure

Populate bats test helper libraries so the existing 47 test files can execute.

## Requirements

- `test/libs/bats-support/`, `test/libs/bats-assert/`, and `test/libs/bats-file/` must contain the respective bats helper libraries
- All 47 existing `.bats` test files must be executable via `bats --jobs 4 test/`
- The install mechanism must be reproducible (git submodules, download script, or documented manual steps)

## Constraints

- The bats helper libraries are standard open-source projects: bats-core/bats-support, bats-core/bats-assert, bats-core/bats-file
- Must work on macOS and Linux
- Must not require root access to install

## Out of Scope

- Writing new tests (existing 47 test files are sufficient)
- CI/CD pipeline configuration
- Test coverage reporting
