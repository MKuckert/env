# Plan: Builder Hard-Stop Protocol (Issue #90)

## Objective

The Builder currently burns up to 500 steps when it hits a wall: a denied command (permission wall), a build failing repeatedly with the same error, or a fix that is out of scope. The plan makes the Builder **stop early and escalate** instead of looping, and gives the Planner a duty to declare required tooling/permissions **before** the build starts.

## Requirements & Decisions

- **Frameworks:** opencode agent harness (`.opencode/agents/`, `.opencode/commands/`, root `AGENTS.md`). No code, config + prompt changes only.
- **Chosen Libraries:** none.
- **Error Handling Strategy:** "Fail loud, never fake" (AGENTS.md). A hard problem ends the Builder's turn with an explicit `## Blocker` artifact in `PLAN.md` and a `question` escalation — never a silent workaround, never a retried denial.
- **Decision (user-visible semantics):** three hard-stop triggers — (1) same build/test command fails 2 consecutive times with the same error signature, (2) required remediation is a denied command/file, (3) fix requires out-of-scope changes.
- **Decision (mechanical backstop):** Builder `doom_loop` flips to `deny` so the platform force-stops repeated identical tool calls; `steps` drops 500 → 100. Prompt protocol is the primary fix; these are backstops, not the fix.

## Required Tooling & Permissions

- **Builder (self-referential, this plan):** only `read`, `edit`, `grep`, `list` — no bash needed. All four files are in-repo and within the Builder's current permission set.

## Implementation Steps

> Status Markers: [ ] Open, [/] In Progress, [x] Completed (set after accepted review only!)

- [x] **Task 1: Builder hard-stop protocol (prompt)**
  - **Description:** In `.opencode/agents/Builder.md` add a `<hard_stop_protocol>` section after `<principles>` defining the three triggers above — with trigger 3 anchored as: *changes not listed in the current task's Description/Review Criteria in `PLAN.md`* — plus two escalation cases: (a) when the step budget is ~80% consumed without task completion, and (b) when CodeReviewer invokes its iteration limit (3-strike breaker). Required exit behavior for all: stop immediately (no retry of a denied command, no workaround), write a `## Blocker` section to `PLAN.md` (error signature / what was tried / the exact permission or change needed), commit the Blocker note via **Committer**, and end the turn by calling `question` to hand control to the user. Add principle 8: "Permission walls are stop signals, not puzzles."
  - **Review Criteria:** Triggers are objective and countable (trigger 3 anchored to PLAN.md task scope); exit behavior names the exact artifact (`## Blocker` in PLAN.md), the commit step (Committer), and the tool (`question`); no ambiguity about retrying denials; reviewer-deadlock and step-budget cases both route into the same exit behavior.
- [x] **Task 2: Builder mechanical backstops (frontmatter)**
  - **Description:** In `.opencode/agents/Builder.md` frontmatter set `doom_loop: deny` and `steps: 100`. During implementation, verify the installed opencode version's doom-loop semantics (repeat threshold, and that `deny` = force-stop rather than ask) — the opencode source is not vendored, so confirm against installed version/docs; if semantics differ, note it in the commit message.
  - **Review Criteria:** YAML still valid; values match the plan decision; no other agent touched; doom-loop semantics check performed and its result recorded.
- [x] **Task 3: Planner permission pre-check**
  - **Description:** In `.opencode/agents/Planner.md`: (a) add a fourth mandatory question to the interrogation phase — **Required Tooling & Permissions:** which commands, tools, and file scopes will the Builder need? (b) add a `## Required Tooling & Permissions` section to the PLAN.md template between "Requirements & Decisions" and "Implementation Steps".
  - **Review Criteria:** Both prompt text and template carry the new question/section; existing mandatory questions untouched.
- [x] **Task 4: Command + protocol doc alignment**
  - **Description:** (a) `.opencode/commands/implement_next_task.md`: add one line — if a hard-stop trigger fires, follow the Builder's hard-stop protocol (write `## Blocker`, escalate via `question`, stop). (b) Root `AGENTS.md` Builder section: add a "Hard Stop" bullet mirroring the three triggers and the Blocker/escalation behavior.
  - **Review Criteria:** Command file stays a one-paragraph trigger; AGENTS.md bullet matches the Builder prompt wording.

## Edge Case & Safety Checklist

- `doom_loop: deny` force-stops on repeated identical calls — legitimate repeated reads (e.g. re-reading PLAN.md) could trip it; accepted as backstop per plan, noted for the user.
- **Step-budget exhaustion:** at `steps: 100` opencode can end the session with no Blocker artifact. Mitigated by trigger (a): at ~80% budget the Builder must write `## Blocker` + escalate, so exhaustion becomes a last resort, not the normal exit path.
- Builder must not write `## Blocker` for transient single failures (1 failure ≠ hard stop; trigger 1 requires 2 consecutive identical-signature failures).
- "Same error signature" = same failing command + same first error line/exit code, not merely both being non-zero.
- Existing review loop (CodeReviewer 3-strike circuit breaker) is untouched — hard stop complements it, does not replace it; the Builder now explicitly treats the breaker firing as a hard stop.
- No changes to other agents' frontmatter or to `opencode.jsonc` (their `doom_loop: allow`/`steps: 500` values are a possible follow-up, out of scope here).

## Review Log (Plan Review)

- **Round 1:** CHANGES REQUESTED — 6 items: (1) step-budget exhaustion had no exit path, (2) CodeReviewer breaker deadlock unhandled, (3) trigger 3 not objective, (4) Blocker commit ownership unspecified, (5) template self-inconsistency in section order, (6) doom_loop semantics unverified. All addressed in this revision.
- **Round 2:** APPROVED. Non-blocking notes for Builder: (1) if doom-loop verification is blocked, proceed with the value change and disclose "verification blocked" in the commit message; `opencode/opencode.jsonc` already documents the 3-repeat semantics and is usable in-repo evidence. (2) Phrase the 80% trigger as self-counted steps — the platform exposes no live step counter.

## Final Status (Code Review)

- **Round 1:** APPROVED (commit 9679775). All four tasks verified against plan; consistency, scope, and frontmatter checks passed.
