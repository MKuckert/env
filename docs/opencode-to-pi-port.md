# OpenCode → pi Harness Port

Port of the OpenCode agent harness (`.opencode/`) to the pi harness, using **local-only
extensions** — no global or system-wide installs.

## Architecture

| Layer | OpenCode | pi (this port) |
|---|---|---|
| Agent loader | built-in `.opencode/agents/*.md` | `pi-open-agents@0.1.20` (discovers the same files, zero format changes) |
| Permissions | built-in `permission:` frontmatter + `opencode.jsonc` | `@gotgenes/pi-permission-system@29.1.0` (session-level gates) + pi-open-agents tool whitelist |
| Subagents | `task` tool, `subagent_depth: 2` | `subagent` tool (child pi processes), `allowedAgents` + `maxDepth` frontmatter |
| Skills | `.opencode/skills/*/SKILL.md` | copied to `.pi/skills/` (same SKILL.md format) |
| Commands | `.opencode/commands/*.md` | converted to prompt templates in `.pi/prompts/*.md` |
| Models | `github-copilot/*`, `claude-*` (pinned) | remapped to local `omlx/qwen3.8-27B-oQ4e` |

### Local extensions

Installed into `.pi/extensions/node_modules/` (reproducible via
`npm install` in `.pi/extensions/`), referenced by absolute path in the project
`.pi/settings.json`:

- `pi-open-agents@0.1.20`
- `@gotgenes/pi-permission-system@29.1.0` (config: `.pi/extensions/pi-permission-system/config.json`)

## What changed in the agent files

1. **Model remap** — all 10 agents → `omlx/qwen3.8-27B-oQ4e`.
   (The initially chosen `oQ5e` variant does not exist in the local omlx registry;
   discovered when CodeReviewer children returned `(no output)`.)
2. **`reasoningEffort:` → `thinking:`** — pi-open-agents 0.1.20 does not alias the old key.
   `high` is not a supported level on this model (`thinkingLevelMap.high = null`),
   so reviewers/planner/testing use `xhigh`.
3. **Nesting fix** (pi-open-agents derives a child's tool whitelist from permission keys
   whose value is exactly `"allow"`; object-valued `task:` maps are ignored):
   - CodeReviewer / PlanReviewer: added `subagent: allow` and
     `allowedAgents: Explorer, Librarian`.
   - Leaves (Explorer, Librarian, Committer): `maxDepth: 0` — a child at/above maxDepth
     gets no `subagent` tool, enforcing the old `subagent_depth: 2`.
   - Committer: explicit pi-style `tools: read, grep, bash` (its pattern-based
     `bash:` map cannot derive a whitelist).
   - pi tool names added alongside opencode ones (`find`, `ls` for `glob`, `list`).
   - Explorer: `edit: allow` so the create-projectmap skill can write `PROJECT_MAP.md`.
4. Dropped inert keys: `steps`, `question`, `doom_loop`, `todowrite` (kept where harmless).

## Verified end-to-end

- Agent discovery + `search_agents` / `set_agent` in the main session.
- Subagent delegation: main → Explorer (structured result returned).
- Permission enforcement in child processes (tool whitelist strips denied tools, e.g. Explorer has no bash).
- **Nested delegation**: CodeReviewer → Explorer succeeds (depth 2); CodeReviewer → Committer
  rejected with `Unknown agent: Committer. Available agents: Explorer, Librarian.`
- Skills visible in the main session (`create-projectmap`, `grilling`).

## Gaps (not enforceable / not ported)

1. **Web stack.** OpenCode wired a local MCP gateway (`localhost:1200x/mcp`) for
   `webfetch`/`websearch`; Librarian has only `web_*: allow`. The gateway is not running in
   this environment, and pi has no native web tools here. Librarian children currently have
   **no usable tools** (all local tools denied, no web). Fix when the gateway is back:
   wire it via `pi-mcp-adapter` and add the MCP tool names to Librarian's allowlist.
2. **Per-agent runtime permission enforcement.** pi-permission-system identifies the active
   agent via `<active_agent name=...>` tags / `active_agent` session entries; pi-open-agents
   child processes write neither (they use an `open-agents-state` entry and a bare system
   prompt). So in child sessions only the *global/project* permission config applies —
   per-agent frontmatter policies are not enforced at call time. Child isolation comes from
   the tool whitelist instead, which is coarser.
3. **Pattern-scoped permissions are not enforced.** pi-open-agents only uses permission
   frontmatter to derive the child's tool whitelist (binary allow/deny per tool). Patterns
   like Committer's git-only bash, or path-scoped `edit` rules (Explorer could only write
   `PROJECT_MAP.md`), are not checked at call time. Mitigations: explicit `tools:` lists,
   and prompt-level instructions in the agent bodies.
4. **Commands.** OpenCode commands carried `agent:` frontmatter (run the command *as* that
   agent). pi prompt templates have no such field; the templates now instruct `set_agent`
   (primary agents) or delegation via the `subagent` tool (subagents). Templates are
   TUI slash commands — not visible to the model in `-p` mode.
5. **`research.md`** referenced the opencode built-in `customize-opencode` skill (absent in
   pi); the template now references pi's own SKILL.md conventions instead.
6. **`opencode.jsonc`** (MCP servers, `subagent_depth`, web denial) has no direct pi
   equivalent; its settings are mirrored by the frontmatter changes above and this doc.

## Sync note

The canonical agent definitions live in the `agent-harness` submodule
(`agent-harness/.opencode/`); root `.opencode/` is a synced copy. The edits in this port
were made to the root copy — run `agent-harness/bin/harness-sync.sh push` (3-way git-apply
sync) to propagate them into the submodule before merging.
