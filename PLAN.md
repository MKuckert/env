# Plan: Persist Librarian Research Results

## Objective

Implement GitHub issue #85 so every Librarian invocation persists its research as a tracked Markdown artifact under the workspace-relative `research/results/` directory, using YAML frontmatter analogous to an OpenCode skill and reporting persistence failures explicitly.

## Requirements & Decisions

- **Frameworks:** Existing OpenCode agent Markdown/frontmatter configuration and built-in `write` plus `glob` tools. OpenCode gates `write` through the `edit` permission and supports path-pattern permission rules. The canonical agent definition lives in `agent-harness/.opencode/` and is synchronized into each workspace through `.harness-sync`.
- **Chosen Libraries:** None. YAML/frontmatter and Markdown are prompt-defined output formats, so adding a serialization dependency would be unnecessary.
- **Error Handling Strategy:** Librarian must persist before returning its final response, report the written path on success, and fail visibly with the target path and tool error if the pre-provisioned destination is missing or writing fails. Research with unavailable or failed sources is saved with `status: partial` and explicit limitations rather than presented as complete. Invalid or missing required metadata prevents writing and is surfaced as an error.
- **Path:** Interpret issue wording `/research/results` as `<invoking workspace>/research/results`, not an absolute filesystem path. Runtime artifacts belong to and remain in that workspace. `agent-harness/research/results/` is only the canonical harness repository's own runtime destination; it is not a source directory to synchronize. Results are version-controlled but not automatically committed.
- **Scope:** Persistence applies to every Librarian run, including direct calls outside the `/research` command.
- **Ownership:** Librarian owns result serialization and persistence. Its final response uses a stable handoff line, `Research artifact: research/results/<filename>.md`; callers consume that path and must not duplicate the artifact.
- **Artifact Contract:** Use one filesystem-safe Markdown filename per run, based on UTC date/time, a normalized topic slug, and a high-entropy suffix. Refuse a filename already found by the collision check rather than overwriting it. Frontmatter mirrors skill conventions with `name`, `description`, and string-valued `metadata` entries for `created`, `libraries`, `tags`, `sources`, `verified`, and `status`. The body contains findings, implementation notes, sources, and limitations.
- **Permissions and Tooling:** Use built-in `write`, authorized by `edit` only for `research/results/*.md`, and built-in `read`, `glob` and `list`, authorized only for `research/results/*.md`, to perform best-effort collision checks. Do not add the broad `fsrw` MCP: its current workspace-wide mount cannot enforce the required per-directory write boundary. Retain denials for built-in shell, external directories, non-result paths, and unrelated tools. Pre-provision the destination because no directory-creation permission is granted to Librarian. Validate the exact path patterns against the installed OpenCode version before changing the agent.
- **Security Boundary:** Permission rules and the pre-provisioned real directory are the enforcement boundary. Prompt instructions provide defense in depth for slugging, frontmatter quoting, provenance, and secret minimization, but cannot guarantee semantic sanitization. Do not follow symlinks: setup/validation must reject a symlinked `research` or `research/results` path.
- **Concurrency Limit:** `glob` followed by `write` is not atomic and the built-in writer can overwrite. Use a timestamp plus high-entropy suffix and refuse a filename already returned by `glob`; document that truly concurrent adversarial collisions cannot be eliminated without a dedicated atomic-create tool and are out of scope for this prompt-only change.

## Implementation Steps

> Status Markers: [ ] Open, [/] In Progress, [x] Completed (set after accepted review only!)

- [/] **Task 1: Define and document the research artifact contract**
  - **Description:** Pre-provision tracked `research/results/` directories with placeholder files in both the canonical `agent-harness` repository and this root workspace as a one-time migration; future consuming workspaces must create their own destination during harness setup. Add canonical documentation/template defining required frontmatter, Markdown sections, invoking-workspace path semantics, ASCII slug rules, UTC timestamp plus high-entropy suffix naming, collision refusal, partial-result handling, and source provenance. Keep all `metadata` values strings to remain analogous to documented OpenCode skill frontmatter. Do not add `research/` to `.harness-sync`.
- [ ] **Task 2: Give Librarian least-privilege persistence access**
  - **Description:** Update `agent-harness/.opencode/agents/Librarian.md` to allow `edit`, `read`, `list` and `glob` only for `research/results/*.md`. Preserve web access and all unrelated denials. Do not grant `bash`, unrestricted MCP filesystem tools, recursive result access, or `external_directory` access.
- [ ] **Task 3: Add persistence to the Librarian workflow**
  - **Description:** Extend the Librarian instructions to normalize its topic to a bounded ASCII slug, collect provenance, quote scalar metadata safely, minimize secrets, validate required metadata, generate a timestamp/high-entropy filename, reject a glob-detected collision, and write before returning. Require the exact `Research artifact: ...` handoff line. Save incomplete research as `partial` with source errors and limitations. If research is partial and persistence also fails, return both failure classes and no success path. Never claim persistence after a failed write.
- [ ] **Task 4: Align the research command and harness documentation**
  - **Description:** Integrate the frontmatter documentation from `agent-harness/.opencode/commands/research.md` into the Librarian agents definition; skip the SKILL creation part. Remove `agent-harness/.opencode/commands/research.md` afterwards. Update `agent-harness/README.md` and setup documentation to describe destination provisioning and narrowly scoped local persistence.

## Edge Case & Safety Checklist

- Empty, punctuation-only, Unicode, very long, or path-like topics produce a bounded safe slug or fail clearly.
- Two runs with the same topic and timestamp use collision suffixes and never overwrite silently.
- Concurrent collision detection/write behavior is tested or explicitly documented as a limitation; a detected collision must be visible.
- Missing `research/results/`, read-only filesystems, denied permissions, and tool errors produce explicit failures naming the target path.
- Empty search results, inaccessible sources, timeouts, API errors, and version ambiguity create a `partial` artifact with limitations and do not claim verification.
- Frontmatter delimiters and user/source text are escaped so arbitrary content cannot corrupt YAML or inject new metadata fields.
- All required metadata values are strings; `verified` defaults to `"false"` until human review.
- Source provenance includes URLs and access outcomes; inaccessible sources are not silently omitted.
- Artifact content excludes credentials, tokens, cookies, and unrelated proprietary prompt context.
- Librarian remains unable to execute shell commands or access files outside `research/results/**`.
- Setup and tests reject symlinked destination components; normalized filenames contain no separators or `..` segments.
- `/research` does not persist a duplicate artifact after Librarian has already written one.
- Synchronization does not copy generated project research between unrelated registered projects.

## Review Log (Plan Review)

- **Round 1:** Changes required: (1) Resolve the destination contradiction: Task 1 creates `agent-harness/research/results/`, while runtime artifacts must be written to each invoking workspace's unsynchronized `research/results/`; distinguish any canonical template/fixture path from the runtime path. (2) Establish feasible tooling before implementation: current `agent-harness/opencode.jsonc` configures only the web MCP and Librarian denies all local tools; identify the exact supported write/create-directory and collision-check tools plus their path-rule syntax, then include any required tool/MCP configuration in scope. (3) Define least-privilege handling for directory creation, symlinks/path traversal, and collision-safe creation; read/list access to all prior research should not be granted unless necessary. (4) Specify the `/research` handoff: it currently runs as Builder and calls Librarian, so define how the artifact path is returned and consumed without duplicate persistence. (5) Define prompt-enforcement limits and tests for untrusted YAML/body content, secret filtering, malformed metadata, and partial research followed by persistence failure; fixtures alone do not prove every invocation persists.
- **Round 2:** Approved
- **Round 3:** N/A

## Final Status (Code Review)

- **Round 1:** Pending
- **Round 2:** N/A
- **Round 3:** N/A
