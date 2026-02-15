# Model Alias Registry

## Overview

A JSON file (`models.json`) that lives next to `ralph.sh` and maps shorthand alias names to backend-specific model IDs. The structure is extensible to support multiple backends (e.g., Bedrock, future vendors like Microsoft Foundry).

## Requirements

- The file must be named `models.json` and located in the same directory as `ralph.sh`.
- Each entry is keyed by a shorthand alias (e.g., `opus-4.6`, `sonnet`, `haiku`).
- Each alias maps to an object with backend keys (e.g., `bedrock`), each containing the full model ID string for that backend.
- Aliases do not need mappings for all backends. Missing backends will pass through the alias as-is.
- The registry must include Bedrock mappings for at least the following model families:
  - `opus-4.6` — Claude Opus 4.6
  - `opus-4.5` — Claude Opus 4.5
  - `sonnet` — Claude Sonnet 4.5
  - `haiku` — Claude Haiku 4.5
- The file must be valid JSON parseable by `jq`.
- Resolution behavior:
  - If alias is found and has a mapping for the active backend: use the mapped model ID
  - If alias is found but has no mapping for the active backend: pass through the alias as-is
  - If alias is not found: pass through the alias as-is

## Constraints

- The file is hand-edited by the user to correct or add model IDs. The format must be human-readable and easy to update.
- Bedrock model IDs in the initial version are best-guess and expected to be corrected manually.
- Adding a new model alias requires only editing `models.json` — no changes to `ralph.sh`.
- The `anthropic` backend does not require mappings in `models.json` since Anthropic model IDs are canonical and can be used directly (e.g., `claude-opus-4-6`, `claude-sonnet-4-5-20250929`).
- The structure supports future backends (e.g., `foundry`, `vertex`) by adding new keys under each alias.

## Out of Scope

- Automatic discovery or validation of model IDs against the Anthropic API or AWS Bedrock.
- Versioning or migration of the models.json format.
- Per-project or per-user override files.
