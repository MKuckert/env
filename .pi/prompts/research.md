---
description: Research into Skill (runs as Builder)
argument-hint: "<topic> [package@version]"
---

First use the set_agent tool to switch to the "Builder" agent.

Your task is to thoroughly research a user-specified technical topic, library, or framework version using the `Librarian` subagent for web search, then compile these findings into a modular, reusable pi Skill (`SKILL.md`).

## Tooling Stack & Skills

1. Use the `Librarian` subagent for discovery:
   - **Web Search:** Discover high-level concepts, recent ecosystem changes, and known architectural patterns.
   - **Documentation:** Extract raw, un-hallucinated, version-specific documentation and official code examples from official sources.
2. **pi Skill format:** Follow the pi skill conventions (frontmatter with `name` and `description`, concise body, SKILL.md layout under `.pi/skills/<skill-name>/`).

## Workflow Execution Steps

### Step 1: Information Gathering & Cross-Referencing

- Accept the target topic, package name, and version from the user.
- Spawn the `Librarian` subagent to run web research to identify breaking changes and architectural best practices. Anchor the research in real, version-accurate documentation. Extract 1-2 pristine, minimal boilerplate code examples.

### Step 2: Formatting Blueprint

- Use the pi skill conventions (frontmatter keys, naming conventions, required sections) for creating a `SKILL.md` file.
- Come up with a good name for the skill.

### Step 3: Synthesis for Machine Consumption

- Translate your findings into explicit instructions tailored for _other AI agents_ (not humans).
- Focus heavily on structural constraints, anti-patterns, required imports, and edge cases that typically cause LLMs to fail.
- Be token sensitive: ensure that the final output is concise, clear, and adheres strictly to the formatting rules.

### Step 4: Output Generation

- Map your technical findings directly into the SKILL.md layout.
- Create the skill under `.pi/skills/<skill-name>/SKILL.md` with a `description` frontmatter field that makes the skill easy to discover.

$ARGUMENTS
