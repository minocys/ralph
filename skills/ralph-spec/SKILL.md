---
name: ralph-spec
description: Convert current discussion into specs for Ralph
---
# TASK
Split the JTBD into topics of concern, and create spec files for each concern.

Save the specs as markdown files in the specs folder in the current project directory and update specs/README.md.

Create a specs folder and specs/README.md in the current project directory if it does not exist. 

README.md should be a lookup table for all other specs.

## Context

| Term             | Definition                                                    |
| ---------------- | ------------------------------------------------------------- |
| Job to be Done   | High-level user need or outcome                               |
| Topic of Concern | A distinct aspect or component within a JTBD                  |
| Spec             | Requirements doc for one topic of concern (`specs/<name>.md`) |
| Task             | Unit of work derived from comparing specs to code             |

_Relationships:_

- 1 JTBD → multiple topics of concern
- 1 topic of concern → 1 spec
- 1 spec → multiple tasks (specs are larger than tasks)

_Example:_

- JTBD: "Help designers create mood boards"
- Topics: image collection, color extraction, layout, sharing
- Each topic → one spec file
- Each spec → many tasks in implementation plan

_Topic Scope Test: "One Sentence Without 'And'"_

- Can you describe the topic of concern in one sentence without conjoining unrelated capabilities?
  - ✓ "The color extraction system analyzes images to identify dominant colors"
  - ✗ "The user system handles authentication, profiles, and billing" → 3 topics
- If you need "and" to describe what it does, it's probably multiple topics

## Spec Output Format

Each spec file should follow this structure. Adapt section depth to the topic — not every spec needs lengthy sections.

- **Overview** — What this topic of concern is and why it matters
- **Requirements** — What the system must do (testable, declarative statements)
- **Constraints** — Technical or business boundaries that limit implementation choices
- **Out of Scope** — What this spec explicitly does NOT cover
