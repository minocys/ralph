# CLI Model Selection

## Overview

New CLI flags for `ralph.sh` that let the user choose a model and backend when launching a ralph session. The model is resolved from a shorthand alias via `models.json` and passed to the `claude` CLI as a `--model` argument.

## Requirements

### New flags

- `--model <alias>` / `-m <alias>` — select a model by shorthand alias.
- `--bedrock` — force the Bedrock backend for this session.
- `--anthropic` — force the Anthropic API backend for this session.
- `--bedrock` and `--anthropic` are mutually exclusive. Passing both must produce an error.

### Backend resolution

- Default backend is determined by the `CLAUDE_CODE_USE_BEDROCK` environment variable in `~/.claude/settings.json`. If `CLAUDE_CODE_USE_BEDROCK` is `"1"`, the default backend is `bedrock`; otherwise it is `anthropic`.
- `--bedrock` overrides the default to `bedrock`.
- `--anthropic` overrides the default to `anthropic`.

### Model resolution

- When `--model` is provided, look up the alias in `models.json`.
- Select the model ID corresponding to the active backend (`anthropic` or `bedrock` key).
- If the alias is not found in `models.json`, exit with an error and list available aliases.
- The resolved model ID is passed to `claude` via the `--model` CLI argument.
- When `--model` is not provided, no `--model` argument is passed to `claude` — the default from `settings.json` is used.

### Environment override

- When `--bedrock` is specified, export `CLAUDE_CODE_USE_BEDROCK=1` before invoking `claude`.
- When `--anthropic` is specified, export `CLAUDE_CODE_USE_BEDROCK=0` before invoking `claude`.
- When neither is specified, do not modify the environment — inherit from `settings.json`.

### Startup banner

- When a model is explicitly selected, display the alias and resolved model ID in the startup banner.
- When a backend override is active, display the active backend in the startup banner.

### Help text

- The `--help` output must document `--model`, `-m`, `--bedrock`, and `--anthropic`.
- The help text should mention that available aliases are listed in `models.json`.

## Constraints

- `ralph.sh` must remain a pure bash script with no dependencies beyond `jq` (already required).
- Model resolution reads `models.json` relative to the script's own directory, not the working directory.
- The `~/.claude/settings.json` file is read-only — `ralph.sh` never writes to it.

## Out of Scope

- Passing full model IDs directly (bypassing aliases).
- Modifying `~/.claude/settings.json` from `ralph.sh`.
- Model-specific behavior changes (e.g., different prompts per model).
- Validation that the resolved model ID is actually available on the selected backend.
