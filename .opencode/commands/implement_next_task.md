---
description: Implements the next open TODO in PLAN.md
agent: Builder
---

Implement the first open task in @PLAN.md.
Trigger the CodeReviewer agent when you're done and address all critique.

If a hard-stop trigger fires (2 consecutive identical failures, a permission denial, an out-of-scope fix, ~80/100 steps consumed, or the reviewer's iteration limit), follow your hard-stop protocol: write `## Blocker` to PLAN.md, commit via Committer, escalate via `question`, and stop.

Stop when you think you're done with this single task for further instructions. Nothing more.

$ARGUMENTS
