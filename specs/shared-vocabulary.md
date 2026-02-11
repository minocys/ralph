# Shared Vocabulary

Distribute the core concepts table to `ralph-plan` so the spec and plan skills share the same terminology, even though they run in isolated sessions.

## Requirements

- `ralph-plan/SKILL.md` must each include the concepts table in its `## Context` section
- The table content must be identical across all three skills:
  ```
  | Term             | Definition                                                    |
  | ---------------- | ------------------------------------------------------------- |
  | Job to be Done   | High-level user need or outcome                               |
  | Topic of Concern | A distinct aspect or component within a JTBD                  |
  | Spec             | Requirements doc for one topic of concern (`specs/<name>.md`) |
  | Task             | Unit of work derived from comparing specs to code             |
  ```
- `ralph-plan/SKILL.md` does NOT need the examples, relationships, or scope test from `ralph-spec` — only the vocabulary table
- `ralph-spec/SKILL.md` retains the full concepts section (table + relationships + examples + scope test) since it is the skill where these concepts are introduced to the user

## Constraints

- The table must be kept in sync — if a term is added or changed, it must be updated in both `ralph-spec` and `ralph-plan` skills
- Do not add vocabulary that is specific to only one skill (e.g., `AGENTS.md` is a ralph-build concept, not a shared term)

## Out of Scope

- Changing term definitions
- Adding new terms to the vocabulary
