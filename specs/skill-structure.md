# Skill Structure

Standardize all three skill prompts (`ralph-spec`, `ralph-plan`, `ralph-build`) to follow the same skeleton so they are consistent and easier to maintain.

## Requirements

- Every SKILL.md must use the same section structure in the same order
- The standard skeleton is:
  ```
  ---
  name: <skill-name>
  description: <one-line description>
  ---
  # TASK
  One-line summary of what this skill does.

  ## Context
  Shared vocabulary and references.

  ## Steps
  Sequential workflow steps, numbered.

  ## Rules
  Non-sequential invariants that apply throughout execution.
  ```
- The `# TASK` heading must be identical across all skills (not `YOUR TASK` or omitted)
- Sequential steps use standard numbering (`1.`, `2.`, `3.`); prerequisite research steps that precede the main loop may use `0a.`, `0b.` etc.
- The escalating-9s numbering system (`99999.`, `999999.`, etc.) in ralph-build must be replaced with a `## Rules` section using grouped bullet points
- Sections may be omitted if genuinely empty (e.g., `ralph-spec` may not need `## Rules`), but the ordering must be preserved when present

## Constraints

- Do not change the semantic content of any instructions during restructuring — this is a formatting change only
- Frontmatter (`---` block with name/description) must be preserved as-is

## Out of Scope

- Changing instruction wording or adding new instructions (handled by other specs)
- Modifying ralph.sh or install.sh
