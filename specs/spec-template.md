# Spec Template

Add output format guidance to `ralph-spec` so generated spec files follow a consistent structure.

## Requirements

- `ralph-spec/SKILL.md` must include a template that defines the expected structure of output spec files
- The template sections are:
  - **Overview** — What this topic of concern is and why it matters
  - **Requirements** — What the system must do (testable, declarative statements)
  - **Constraints** — Technical or business boundaries
  - **Out of Scope** — What this spec explicitly does NOT cover
- The template should be presented as guidance, not rigid scaffolding — the model may adapt section depth to the topic
- The template should appear after the concepts section and before any other instructions

## Constraints

- Keep the template minimal — enough for consistency, not so much that it constrains useful variation
- Do not prescribe formatting within sections (e.g., bullet vs. prose)

## Out of Scope

- Changing the concepts table or scope test content
- Defining how specs are consumed by downstream skills (that's ralph-plan's concern)
