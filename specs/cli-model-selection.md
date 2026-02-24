# CLI Model Selection

## Overview

New CLI flags for `ralph.sh` that let the user choose a model and backend when launching a ralph session. The model is resolved from a shorthand alias via `models.json` and passed to the `claude` CLI as a `--model` argument.

## Requirements

### Flags

- `--model <alias>` / `-m <alias>` — select a model by shorthand alias. Applies to both `ralph plan` and `ralph build` subcommands.

### Backend resolution

Backend is determined by checking `CLAUDE_CODE_USE_BEDROCK` in order of precedence:

1. **Environment variable** (inline or exported): `CLAUDE_CODE_USE_BEDROCK=1 ./ralph.sh`
2. **Local settings (project-specific, git-ignored)**: `./.claude/settings.local.json` → `.env.CLAUDE_CODE_USE_BEDROCK`
3. **Local settings (project-level)**: `./.claude/settings.json` → `.env.CLAUDE_CODE_USE_BEDROCK`
4. **User settings (fallback)**: `~/.claude/settings.json` → `.env.CLAUDE_CODE_USE_BEDROCK`

If `CLAUDE_CODE_USE_BEDROCK` equals `"1"` (from any source), the backend is `bedrock`; otherwise it is `anthropic`.

The active backend is displayed in the startup banner.

### Model resolution

- When `--model` is not provided, no `--model` argument is passed to `claude` — the default from `settings.json` is used.
- When `--model` is provided:
  - Look up the alias in `models.json`
  - If found, use the model ID for the active backend key (e.g., `bedrock`)
  - If the alias exists but has no mapping for the active backend, pass through the alias as-is
  - If the alias is not found in `models.json`, pass through the alias as-is
- The resolved/pass-through model ID is passed to `claude` via the `--model` CLI argument.

### Startup banner

- Display the active backend (`anthropic` or `bedrock`) in the startup banner
- When a model is explicitly selected, display the alias and resolved/pass-through model ID

### Help text

- `ralph plan --help` and `ralph build --help` must document `--model`, `-m`
- The help text should mention that available aliases are listed in `models.json`

## Constraints

- `ralph.sh` must remain a pure bash script with no dependencies beyond `jq` (already required)
- Model resolution reads `models.json` relative to the script's own directory, not the working directory
- Settings files (`./.claude/settings.json`, `./.claude/settings.local.json`, `~/.claude/settings.json`) are read-only — `ralph.sh` never writes to them
- Model and backend resolution applies to both `ralph plan` and `ralph build` subcommands

## Testing

### Framework

Use [bats-core](https://github.com/bats-core/bats-core) (Bash Automated Testing System) for all `ralph.sh` tests. Bats is a TAP-compliant testing framework purpose-built for Bash.

### Helper libraries

Install the following bats helper libraries as git submodules under `test/libs/`:

- **bats-support** (`bats-core/bats-support`) — core helper library required by bats-assert.
- **bats-assert** (`bats-core/bats-assert`) — assertion functions: `assert_success`, `assert_failure`, `assert_output`, `assert_line`, `refute_output`, etc.
- **bats-file** (`bats-core/bats-file`) — file-existence assertions: `assert_file_exists`, `assert_dir_exists`, etc.

### Test file layout

```
test/
├── libs/
│   ├── bats-support/   # git submodule
│   ├── bats-assert/    # git submodule
│   └── bats-file/      # git submodule
├── test_helper.bash    # shared setup: load libs, set SCRIPT_DIR, create fixtures
├── ralph_args.bats     # argument parsing tests
├── ralph_preflight.bats # preflight check tests
└── ralph_model.bats    # model/backend resolution tests
```

### Shared test helper (`test/test_helper.bash`)

- Load `bats-support`, `bats-assert`, and `bats-file` via `bats_load_library` or `load` from `test/libs/`.
- Set `SCRIPT_DIR` to the project root so the script under test can locate `models.json`.
- Provide a `setup` function that creates a temporary working directory (`$BATS_TMPDIR`) with a minimal `specs/` directory so preflight checks pass when not under test.
- Provide a `teardown` function that cleans up temp files.

### Test cases

#### `ralph_args.bats` — argument parsing

| # | Test | How |
|---|------|-----|
| 1 | `--help` prints usage and exits 0 | `run ./ralph.sh --help` → `assert_success` + `assert_output --partial "Usage"` |
| 2 | `-h` is an alias for `--help` | Same as above with `-h` |
| 3 | Unknown subcommand exits 1 with error | `run ./ralph.sh bogus` → `assert_failure` + `assert_output --partial "Unknown command"` |
| 4 | `--max-iterations` without value exits 1 | `run ./ralph.sh build -n` → `assert_failure` + `assert_output --partial "requires a number"` |
| 5 | `ralph plan` sets plan mode | `run ./ralph.sh plan ...` and verify mode is reflected in banner output |
| 6 | `ralph build` sets build mode | `run ./ralph.sh build ...` and verify mode is reflected in banner output |
| 7 | `--danger` flag is accepted | Verify banner shows `NO (--dangerously-skip-permissions)` |
| 8 | Multiple flags combine correctly | `run ./ralph.sh plan -n 2 --danger` → banner includes plan mode, iteration cap, and danger notice |

#### `ralph_preflight.bats` — preflight checks

| # | Test | How |
|---|------|-----|
| 1 | Missing `specs/` directory exits 1 | Remove the specs dir before run → `assert_failure` + `assert_output --partial "No specs found"` |
| 2 | Empty `specs/` directory exits 1 | Create empty specs dir → `assert_failure` + `assert_output --partial "No specs found"` |

#### `ralph_model.bats` — model & backend resolution

| # | Test | How |
|---|------|-----|
| 1 | `--model opus-4.5` resolves to bedrock ID when bedrock backend | Mock settings with `CLAUDE_CODE_USE_BEDROCK: "1"` → run with `ralph build --model opus-4.5` → assert banner contains the bedrock model ID |
| 2 | `--model opus-4.5` passes through on anthropic backend | Mock anthropic backend → run with `ralph build --model opus-4.5` → assert banner contains `opus-4.5` (no mapping exists for anthropic) |
| 3 | Unknown alias passes through as model ID | `run ./ralph.sh build --model nonexistent` → `assert_success` + `assert_output --partial "nonexistent"` (raw value used as model ID) |
| 4 | No `--model` flag omits `--model` from claude args | Run without `--model` → verify `--model` is NOT in the constructed claude command |
| 5 | `--model` with each alias in `models.json` succeeds | Loop over all keys in `models.json` and assert each resolves without error |
| 6 | `-m` is an alias for `--model` | `run ./ralph.sh build -m opus-4.5` → same result as `--model opus-4.5` |
| 7 | Environment variable `CLAUDE_CODE_USE_BEDROCK=1` selects bedrock | Set env var before running → assert bedrock backend in banner |
| 8 | Inline env var takes precedence over all settings files | Mock all settings with anthropic → run with `CLAUDE_CODE_USE_BEDROCK=1 ./ralph.sh` → assert bedrock |
| 9 | `./.claude/settings.local.json` takes precedence over `./.claude/settings.json` | Set different backends in each → assert local.json wins |
| 10 | `./.claude/settings.json` takes precedence over `~/.claude/settings.json` | Set different backends in each → assert local wins |
| 11 | Backend is shown in startup banner | Both backends → assert "Backend: anthropic" or "Backend: bedrock" in output |

### Testing technique: isolate from `claude` CLI

Because `ralph.sh` ultimately invokes `claude` (which is not available in CI), tests must **stub** the `claude` command. The recommended approach:

- In the test helper, create a fake `claude` script in a temp directory that simply prints its received arguments and exits 0.
- Prepend that directory to `PATH` so the stub is invoked instead of the real `claude`.
- Tests that verify `--model <id>` is passed to `claude` can then inspect the stub's captured arguments.

### Running tests locally

```bash
# Install bats-core (macOS)
brew install bats-core

# Or via npm
npm install -g bats

# Initialize submodules (first time)
git submodule update --init --recursive

# Run all tests
bats test/

# Run a specific test file
bats test/ralph_args.bats

# TAP output for machine consumption
bats --tap test/
```

## CI/CD — GitHub Actions

### Workflow file

Create `.github/workflows/test.yml`:

```yaml
name: Tests

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  bats:
    name: BATS tests
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Install jq
        run: sudo apt-get install -y jq

      - name: Setup BATS
        uses: mig4/setup-bats@v1
        with:
          bats-version: 1.11.1

      - name: Run tests
        run: bats --tap test/
```

### CI requirements

- The workflow triggers on pushes to `main` and on pull requests targeting `main`.
- `actions/checkout@v4` with `submodules: recursive` ensures the bats helper libraries in `test/libs/` are available.
- `mig4/setup-bats@v1` installs the specified bats-core version onto the runner.
- `jq` is pre-installed on GitHub-hosted runners, but the explicit install step ensures it.
- The `claude` CLI is **not** installed in CI — the stub approach described above makes this unnecessary.

## Out of Scope

- Modifying `~/.claude/settings.json` from `ralph.sh`.
- Model-specific behavior changes (e.g., different prompts per model).
- Validation that the resolved model ID is actually available on the selected backend.
