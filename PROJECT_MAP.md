# Project Map

**Scope note:** This repo is a personal, monorepo-style dev environment. This map is
scoped deliberately to the `nono/` sandbox-launcher subsystem (`nono-here.sh` and its
templates), which is the one coherent, actively-developed feature area as of this
writing. Everything else in the repo (`mtplx/`, `llama.cpp/`, `llama-benchy/`,
`colima/`, `direnv/`, `omlx/`, `manifest/`, `dotfiles/`, and the top-level dotfiles)
is unrelated personal infrastructure with no dependency on `nono/`. It is covered in
one short section at the end so a newcomer knows to ignore it rather than assuming
it is part of the same system.

## Overview

`nono-here.sh` solves "cold repo to running, sandboxed AI agent in one command."
Given any directory inside a git repo, it either hands control straight to an
already-provisioned local harness, or interactively provisions one from a bundled
template (picking a sandbox profile, generating config, wiring hooks) and then hands
over — without the caller needing to know which state the repo is in beforehand.

## Main Execution Flow

The entry point is `nono/nono-here.sh` (`# VERSION 2`), invoked directly or via a
symlink. It resolves its own directory first (`resolve_script_dir`, a hand-rolled,
bounded symlink-following loop — no `readlink -f`/`realpath`, since the script must
run on macOS's stock Bash 3.2) and sets `NONO_HERE_HOME` from that. It then resolves
the workspace root with `git rev-parse --show-toplevel || $PWD` (line 49).

From there, control forks into two paths that both converge on a single function,
`handover()` (line 57) — the sole `exec` call site in the script, by design (decision
B5 in the plan review). This unification exists specifically so the fast path and the
provisioning path are behaviourally indistinguishable to the harness that receives
control.

- **Fast path:** if `$workdir/run_harness.sh` already exists, is a regular file, and
  is executable, and `.sandbox/start.sh` is present and executable, `handover()` is
  called immediately (line 70). Nothing is written to stdout/stderr; nothing on disk
  changes.
- **Provisioning path:** taken only when `run_harness.sh` is absent entirely. It
  proceeds through a strict, plan-mandated order — select a harness → resolve and
  fully validate a template (presence *and* executable bits, both checked before
  anything is deleted) → prompt about a stale `.sandbox` if one exists → `cp -R` the
  template in → `mv` the template's `run_harness.sh` out to the workspace root →
  generate `.sandbox/defaults.sh` (or preserve one the template shipped) → call
  `handover()`.

`handover()` itself does `cd "$workdir" && exec ./run_harness.sh "$@"`. The deployed
`run_harness.sh` sources `.sandbox/defaults.sh` for `SANDBOX_COMMAND` /
`SANDBOX_COMMAND_DEFAULTS`, prepends the latter to argv when appropriate, and execs
`.sandbox/start.sh "$SANDBOX_COMMAND" "$@"`. `start.sh` checks for the external `nono`
binary (exit 127 if missing — this is the only place that dependency is checked),
diffs the workspace `profile.json` against `profile.template.json` via `jq` (with a
degraded `diff`-only fallback if `jq` is absent), runs `before`/`after` hooks around
the session, and finally execs `nono wrap`.

So there are four handover points in total (`nono-here.sh` → `run_harness.sh` →
`start.sh` → `nono wrap`), but only one of them — the first — is owned by
`nono-here.sh`'s own logic; the rest belong to the provisioned template.

## Module Map

### `nono-here.sh` (entry point / provisioner)

- **Responsibilities:** Workspace + self-location resolution; fast-path detection;
  interactive or env-driven harness selection; template discovery with 4-way
  precedence; template validation; stale-`.sandbox` handling; copying/wiring a new
  sandbox; single handover to `run_harness.sh`.
- **Importance:** The entire feature's control surface. Every user-visible behaviour
  (including all ten non-zero exit codes) originates here.
- **Interactions:** Reads `$HOME/.nono-here/templates/*` and `$NONO_HERE_HOME/templates/*`
  (`NONO_HERE_HOME` defaults to the script's own resolved directory, i.e. `nono/`).
  Writes into `$workdir/.sandbox/` and `$workdir/run_harness.sh`. Execs into
  `run_harness.sh`, never returns on success.
- **Key Processes:** `resolve_script_dir` (line 21, bounded 40-hop symlink loop);
  the branch ladder at lines 62–71 (exit 9 for wrong file type, exit 2 for missing
  `+x`, exit 3 for a broken `.sandbox/start.sh`, else handover); harness selection
  (lines 77–101, `NONO_HERE_HARNESS` override or `select` menu, exit 8/4/10); template
  probe (lines 106–124, first-existing-wins, exit 5); template validation (lines
  129–136, exit 7 — checked *before* anything is deleted, per review blocker B1/R2-1);
  stale-sandbox prompt (lines 142–159, exit 6, gated on TTY, requires literal `y`/`Y`,
  never `-f`); copy + move + defaults generation (lines 171–201); final
  `handover "$@"` (line 207, added as Task 8b — see High-Risk Areas).
- **Code Anchors:** `nono/nono-here.sh:57` (`handover()`), `:62` (branch ladder),
  `:106` (template probe), `:142` (stale-sandbox prompt), `:207` (final handover call).

### `nono/templates/default/` (the template bundle)

- **Responsibilities:** The four artifacts `nono-here.sh` copies into a fresh
  workspace: `run_harness.sh`, `start.sh`, `profile.template.json`, `hooks/`.
- **Importance:** This is what a "provisioned sandbox" actually consists of; changes
  here define behaviour for every future `nono-here.sh` run, but do **not**
  retroactively affect already-provisioned workspaces (see High-Risk Area 2).
- **Interactions:** Copied wholesale via `cp -R "$template/." "$workdir/.sandbox/"`;
  `run_harness.sh` is then `mv`'d out of `.sandbox` to the workspace root.
- **Key Processes:** `run_harness.sh` (`# VERSION 3`) sources `defaults.sh`, guards
  `SANDBOX_COMMAND_DEFAULTS` with the Bash-3.2-safe `${arr[@]+"${arr[@]}"}` idiom
  (line 21) — the fix Task 10 made — and calls `start.sh`. `start.sh` owns the `nono`
  binary check, the `profile.json`/`profile.template.json` version diff, and
  `run_hook before`/`after` around `nono wrap`.
- **Code Anchors:** `nono/templates/default/run_harness.sh:21` (empty-array guard),
  `nono/templates/default/start.sh:48` (`run_hook`, see High-Risk Area 1).

### `nono/test_nono_here.sh` (test suite)

- **Responsibilities:** End-to-end coverage of `nono-here.sh`'s exit-code contract.
- **Importance:** The only executable specification of the exit-code map; also the
  only place that exercises the provisioning path at all (production has no
  automated coverage otherwise).
- **Interactions:** Runs the real script under `mktemp -d` fixtures with `HOME` and
  `NONO_HERE_HOME` scrubbed via `env -u`; drives provisioning exclusively through
  `NONO_HERE_HARNESS` (never a test-only hook — that approach was explicitly rejected
  in plan review, decision Q22a) so the tested path is the shipped path.
- **Key Processes:** 16 case groups / 28 sub-cases, plain Bash (no `bats`/`jq`/`rsync`,
  decision Q20b), directory-digest fixtures (`dir_digest`, `find | sort | shasum`) to
  assert byte-for-byte non-mutation where required, and `find_bashes` which locates
  every `bash` on `PATH` and WARNs loudly on stderr if none report as Bash-3.2-era —
  visible degradation instead of a silently-meaningless pass (see High-Risk Area
  discussion of the near-bug this replaced).
- **Code Anchors:** exit codes 2–9 are each asserted at exactly one case group;
  exit 1 and exit 10 are consciously excluded and documented as such in the file
  header (see High-Risk Areas).

### This repo's own `.sandbox/` and root `run_harness.sh`

- **Responsibilities:** None architecturally — these are a live, git-tracked,
  already-provisioned instance of the template, i.e. this repo dogfoods its own
  feature.
- **Importance:** Useful as a real-world example of the template in use. After
  PR #110's review fixes it is current with the template (the former drift in
  High-Risk Areas 1 and 2 below was closed by renaming the template hooks and
  syncing the deployed scripts).
- **Interactions:** None with the rest of the codebase; only with `nono-here.sh`'s
  fast path at invocation time.
- **Code Anchors:** `run_harness.sh` (root, `# VERSION 3`, identical to the template);
  `.sandbox/start.sh` (`# VERSION 3`, body identical to the template); `.sandbox/hooks/before`,
  `.sandbox/hooks/after` (the template now ships these names directly).

## High-Risk Areas

1. **Hook filename mismatch — fixed in PR #110 review.** `templates/default/start.sh`'s
   `run_hook` resolves `"$SANDBOX_DIR/hooks/$1"` and is invoked as `run_hook before` /
   `run_hook after`; the template now ships `hooks/before` and `hooks/after` directly
   (renamed from `before-template`/`after-template`), so fresh provisions fire both
   hooks. Remaining caveat: `run_hook` only executes a hook if it is `-x`; a
   present-but-non-executable hook is silently skipped with no warning.
2. **Template/deployed version drift — closed for this PR, still no upgrade
   mechanism.** The bundled `templates/default/run_harness.sh` and this repo's deployed
   root `run_harness.sh` are both `# VERSION 3`; `.sandbox/start.sh`'s body is
   identical to the template's. `start.sh` diff-checks `profile.json` against
   `profile.template.json` via `.meta.version`, but there is no equivalent check for
   `run_harness.sh`/`start.sh` themselves: once copied into a workspace, they go
   stale silently, forever, with no signal to the user.
3. **The `# VERSION` marker is decorative.** It is written by hand at exactly two
   sites (`nono-here.sh:3`, `templates/default/run_harness.sh:2`) and read by nothing
   anywhere in the codebase. Do not assume a drift-detection mechanism exists on the
   strength of seeing this comment — this was explicitly checked by grep during Task
   10's review and confirmed absent.
4. **Two divergent `profile.template.json` files.** The generic one shipped in
   `nono/templates/default/` differs substantially from this repo's own
   `.sandbox/profile.template.json` (different `extends`, an absolute personal
   `$schema` path, personal `allow`/`deny`/`read_file` lists, extra env vars). Easy to
   edit the wrong one when intending to change either the shipped default or this
   repo's personal profile.
5. **`.harness-sync`** at the repo root declares `.opencode/`, `opencode.jsonc`, and
   `tui.jsonc` as synced from an external upstream (`main=…/agent-harness`) pinned at
   a specific commit. This is undocumented in the README; local edits to those paths
   may silently diverge from or be overwritten by a future sync.
6. **The stale-`.sandbox` deletion is real `rm -r`.** It is gated only by an
   interactive TTY prompt requiring an explicit `y`/`Y`; there is deliberately no
   non-interactive override and deliberately no `-f`. This is intentional (Fail Loud
   over convenience) but worth knowing before scripting around this tool.
7. **Exit codes 1 and 10 are untested by design**, documented as such in
   `test_nono_here.sh`'s header — a trust-but-don't-verify gap that is deliberate,
   not an oversight, but still a real gap in automated coverage.

## Adjacent, unrelated

`mtplx/`, `llama.cpp/`, `llama-benchy/`, `colima/`, `direnv/`, `omlx/`, `manifest/`,
`dotfiles/`, and the top-level `macos/`, `ssh/`, `docker/` etc. directories are
independent personal infrastructure (local LLM tooling, container/VM setup, shell
dotfiles) with no code or data dependency on `nono/`. They are not part of this
feature and are omitted from this map beyond this note.
