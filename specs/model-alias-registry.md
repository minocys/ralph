# Model Alias Registry

## Overview

A JSON file (`models.json`) that lives next to `ralph.sh` and maps shorthand alias names to their full model IDs for both the Anthropic API and AWS Bedrock backends. This is the single source of truth for which models ralph can target.

## Requirements

- The file must be named `models.json` and located in the same directory as `ralph.sh`.
- Each entry is keyed by a shorthand alias (e.g., `opus`, `sonnet`, `haiku`).
- Each alias maps to an object with exactly two keys: `anthropic` and `bedrock`, each containing the full model ID string for that backend.
- The registry must include aliases for at least the following model families:
  - `opus-4.6` — Claude Opus 4
  - `opus-4.5` — Claude Opus 4.5
  - `sonnet` — Claude Sonnet 4
  - `haiku` — Claude 3.5 Haiku
- The file must be valid JSON parseable by `jq`.
- ralph.sh should pass through the model ID if it does not match any of the aliases defined in `models.json`

## Constraints

- The file is hand-edited by the user to correct or add model IDs. The format must be human-readable and easy to update.
- Bedrock model IDs in the initial version are best-guess and expected to be corrected manually.
- Adding a new model alias requires only editing `models.json` — no changes to `ralph.sh`.

## Out of Scope

- Automatic discovery or validation of model IDs against the Anthropic API or AWS Bedrock.
- Versioning or migration of the models.json format.
- Per-project or per-user override files.
