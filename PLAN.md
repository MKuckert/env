# Plan: nono-here.sh — zero-config sandbox bootstrap for AI agent harnesses

## Objective

`nono/nono-here.sh` becomes a self-contained, relocatable entry point that can be invoked from
any directory. It resolves the workspace, and either (a) hands straight over to an already
provisioned `run_harness.sh`, or (b) interactively provisions `.sandbox/` from a template for a
chosen harness and then hands over. One command takes a cold repository to a running,
sandboxed agent.

Secondary objective: fix a latent `set -u` argv bug in `templates/default/run_harness.sh`.

## Requirements & Decisions

- **Frameworks:** Plain Bash (`#!/usr/bin/env bash`, `set -euo pipefail`), consistent with all
  existing scripts under `nono/`. External runtime dependency `nono` is checked by
  `.sandbox/start.sh`, not by `nono-here.sh`.
- **Chosen Libraries:** None. No `rsync`, no `bats`, no `jq` added. Tests are plain Bash
  (decision Q20b) to preserve the repo's dependency-averse style.
- **Error Handling Strategy:** Fail Loud, Never Fake. Every abort writes a `$SELF`-prefixed
  message to stderr with a distinct exit code and, where a fix exists, names it (`chmod +x …`).
  No silent defaults, no silent fallbacks, no destructive `-f`. The single interactive
  destructive action (removing a stale `.sandbox`) requires explicit `y` confirmation.

### Settled design decisions (interrogation record)

| # | Decision |
|---|---|
| Q1/Q11/Q18 | `.sandbox` exists but `run_harness.sh` missing ⇒ warn, prompt `[y/N]`. On `y`: `rm -r` (**never** `-f`) the old `.sandbox`, then fresh copy. No backup directory. |
| Q2/Q12 | Executable bit is required on both `run_harness.sh` and `.sandbox/start.sh`; verified on the shortcut path *and* after a fresh copy. |
| Q3 | All args forwarded verbatim: `exec "$workdir/run_harness.sh" "$@"`. |
| Q4 | After provisioning, exec `run_harness.sh` immediately. |
| Q5 | Harness chosen via Bash `select`. Non-TTY stdin ⇒ abort (harnesses need a TTY anyway). |
| Q6/Q22 | `NONO_HERE_HARNESS` env var overrides the menu. Validated against the closed list; unknown value ⇒ abort. Reinstated after plan review: without it the entire provisioning path is untestable by construction, and routing around that with a test-only hook would mean shipped behaviour is never the tested behaviour. No positional arg or flag (both collide with Q3 arg forwarding). |
| Q7 | Closed harness list, held in one easily extended array at the top of the script. |
| Q8 | A template-provided `.sandbox/defaults.sh` is preserved; the stub is generated only when absent. |
| Q9 | No template found ⇒ abort, listing all four probed paths in order. |
| Q10 | `.sandbox/` and `run_harness.sh` are intended to be committed; the script never touches the workspace `.gitignore`. |
| Q13 | `cp -R "$template/." "$sandbox/"` — dotfile- and mode-preserving, portable. |
| Q14 | Generate `SANDBOX_COMMAND_DEFAULTS=()` **and** fix the `set -u` empty-array handling in the template's `run_harness.sh` — at the *use* site, not by re-assigning the array (see Task 10). Bump its `# VERSION`. |
| Q15 | Strict order: workdir → shortcut check → prompt → **template resolution + validation** → stale-`.sandbox` prompt → `rm -r` → copy → move → defaults → exec. Nothing is ever deleted before a valid replacement template has been located and validated. |
| Q16 | `NONO_HERE_HOME` defaults to the script's own resolved directory (symlinks followed), not a hardcoded `~/env/nono`. |
| Q17 | Workdir resolution reuses the existing idiom as-is; submodule/bare-repo quirks accepted. Resolved workdir is printed before acting. |
| Q19 | An existing workspace `run_harness.sh` is never moved or overwritten. Three paths only: executable ⇒ exec; non-executable ⇒ abort; absent ⇒ move template copy in. |
| Q21 | `# VERSION 2` marker retained in `nono-here.sh`. |

### Exit code map

| Code | Meaning |
|------|---------|
| 0 | Success (or `exec` handover) |
| 1 | Unexpected internal error — an uncaught `set -e` failure, or a `cd "$workdir"` that fails in `handover()` (R2-5). Not a user-facing contract. |
| 2 | Workspace `run_harness.sh` exists but is not executable (user-fixable: `chmod +x`) |
| 3 | Workspace `.sandbox/start.sh` missing or not executable (user-fixable: `chmod +x`) |
| 4 | Harness selection impossible: stdin is not a TTY and `NONO_HERE_HARNESS` is unset |
| 5 | No template directory found (all four candidates probed) |
| 6 | Stale `.sandbox` not replaced: user declined, or the run is non-interactive |
| 7 | Template is malformed: missing `run_harness.sh`/`start.sh`, or they lack `+x` |
| 8 | `NONO_HERE_HARNESS` set to a value outside the closed harness list |
| 9 | Workspace `run_harness.sh` path exists but is not a regular file (directory, dangling symlink, socket) |
| 10 | Harness selection aborted by the user (EOF/Ctrl-D at the `select` prompt) |

Codes 2/3 denote a *workspace* defect the user can fix in place; code 7 denotes a *template*
defect (including missing exec bits detected after the copy in Task 7), so the two causes the
reviewer flagged as overloaded are now distinct.


## Implementation Steps

> Status Markers: [ ] Open, [/] In Progress, [x] Completed (set after accepted review only!)

- [ ] **Task 1: Script skeleton, self-location and workdir resolution**
  - **Description:** Flesh out `nono/nono-here.sh` keeping `#!/usr/bin/env bash`,
    `set -euo pipefail` and `# VERSION 2`. Add `SELF="$(basename "$0")"` and a
    `die <code> <msg…>` helper writing to stderr. Resolve the script's own directory by
    following symlinks in a portable loop (no GNU `readlink -f`, no `realpath` — macOS
    compatibility): iterate `while [[ -L $src ]]` resolving relative targets against their
    parent. Set `NONO_HERE_HOME="${NONO_HERE_HOME:-$script_dir}"`. Resolve
    `workdir=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")`. Echo it to stderr
    **only when provisioning is about to occur** — never on the fast path, which is the common
    case and must add no noise to the harness's own output (N13).
    Note (N16): this is the `git rev-parse` idiom's third occurrence in the repo. Accepted
    deliberately — the three scripts must stay independently executable, and a shared library
    for one line would be over-engineering. Recorded so it is not re-flagged at code review.
  - **Review Criteria:** `NONO_HERE_HOME` correctly derived when the script is invoked via a
    symlink from another directory; an explicitly exported `NONO_HERE_HOME` wins; workdir is
    the git root inside a repo and `$PWD` outside one; the fast path emits nothing on success.

- [ ] **Task 2: Fast path — hand over to an existing `run_harness.sh`**
  - **Description:** Test the workspace path in this order, so no case falls through
    unhandled (B4):
    1. `[[ -e $workdir/run_harness.sh || -L $workdir/run_harness.sh ]]` but **not**
       `[[ -f … ]]` ⇒ `die 9`. This covers a directory named `run_harness.sh`, a dangling
       symlink and other non-regular files. Without this, Task 7's `mv` would move the
       template file *into* such a directory — a silent, wrong success.
    2. `-f` but not `-x` ⇒ `die 2`, naming `chmod +x "$workdir/run_harness.sh"`.
    3. `-f` and `-x` ⇒ require `$workdir/.sandbox/start.sh` to exist and be executable, else
       `die 3`. Then `handover "$@"` (Task 9).
    4. Nothing at that path ⇒ fall through to Task 3. This is the only branch that continues.
    No prompting occurs on this path.
  - **Review Criteria:** All four branches are reachable and tested; a directory named
    `run_harness.sh` exits 9 and is never written into; args (including flags such as
    `--resume` and args containing spaces) arrive verbatim; both exec-bit checks abort with
    the documented codes and actionable messages.

- [ ] **Task 3: Harness selection**
  - **Description:** Declare `HARNESSES=(claude opencode codex copilot pi)` as a single
    top-of-file array (the documented extension point). Resolution order:
    1. If `NONO_HERE_HARNESS` is set and non-empty, validate it against `HARNESSES`; on a
       match use it and skip the menu, otherwise `die 8` printing the offending value and the
       valid list. Never fall back to the menu on an invalid override — a typo'd value must
       fail, not silently prompt.
    2. Else, if `[[ ! -t 0 ]]`, `die 4` listing the valid values and naming
       `NONO_HERE_HARNESS` as the non-interactive route.
    3. Else present a Bash `select harness in "${HARNESSES[@]}"` menu with `PS3="harness> "`.
       On invalid input the *result variable* `$harness` is empty while `$REPLY` holds the raw
       input (S6 — the earlier description had this inverted); so: re-prompt with a warning
       whenever `$harness` is empty, and `break` only once it is non-empty. `select` exits its
       loop on EOF (Ctrl-D) leaving `$harness` unset — detect that after the loop and
       `die 10`, never default.
  - **Review Criteria:** Adding a harness is a one-token array edit with no other change;
    a valid `NONO_HERE_HARNESS` produces a fully non-interactive run; an invalid one exits 8
    without prompting; invalid menu input re-prompts; Ctrl-D exits 10 and non-TTY-without-
    override exits 4; nothing is written to or deleted from disk before a valid selection
    exists.

- [ ] **Task 4: Template resolution and validation**
  - **Description:** Probe, in order and stopping at the first existing directory:
    `$HOME/.nono-here/templates/$harness`, `$HOME/.nono-here/templates/default`,
    `$NONO_HERE_HOME/templates/$harness`, `$NONO_HERE_HOME/templates/default`. If none exist,
    `die 5` printing all four candidate paths in probe order, one per line. Echo the selected
    template     path to stderr. Validate that the template contains `run_harness.sh` and `start.sh` **and
    that both are executable**; if not, `die 7` naming the template path and the offending
    file. The exec-bit assertion must live *here*, not after the copy: a template with dropped
    mode bits (the zip/checkout scenario) would otherwise pass validation, Task 5 would delete
    the user's `.sandbox`, and the run would then abort — leaving neither a sandbox nor a
    harness (R2-1).
  - **Review Criteria:** Precedence honoured exactly, including the user-override-before-
    bundled ordering; the not-found message is self-diagnosing (all four paths visible); both
    the presence *and* the permission checks fire before any destructive or write operation —
    verified by a test that makes a template's `start.sh` non-executable and asserts a
    pre-existing `.sandbox` survives.


- [ ] **Task 5: Stale `.sandbox` handling**
  - **Description:** Reached only when `run_harness.sh` is absent **and** a valid template has
    already been resolved (Task 4) — so the deletion below can never leave the user with
    neither a sandbox nor a replacement. If `$workdir/.sandbox` exists, warn (yellow, stderr,
    matching `start.sh`'s ANSI style) that the sandbox is incomplete, name the template that
    will replace it, and prompt
    `delete .sandbox and re-create from <template>? [y/N] `,     read with `read -r` (N14).

    Accept only `y`/`Y`; anything else
    ⇒ `die 6`. On confirmation run `rm -r "$workdir/.sandbox"` — explicitly **without** `-f`,
    so write-protected content surfaces rather than being force-destroyed.
    **Non-TTY case:** with `NONO_HERE_HARNESS` set, execution can now reach this point without
    a TTY. There is deliberately no non-interactive override for the deletion — if stdin is
    not a TTY, `die 6` immediately with a message instructing the user to remove `.sandbox`
    manually. Destructive actions require a human; scripted runs never delete.
  - **Review Criteria:** `-f` appears nowhere in the script; declining leaves the directory
    byte-for-byte untouched and exits 6; a non-TTY run never deletes anything; accepting
    removes it; a `rm -r` failure propagates (via `set -e`) instead of being swallowed; no
    code path reaches the `rm` without a validated template in hand.

- [ ] **Task 6: Copy template to `.sandbox`**
  - **Description:** `mkdir -p "$workdir/.sandbox"` then `cp -R "$template/." "$workdir/.sandbox/"`
    so dotfiles (`.gitignore`) and modes are preserved without `rsync`.
  - **Review Criteria:** `.gitignore`, `hooks/`, `profile.template.json`, `start.sh` all
    present afterwards; `start.sh` and the hook templates retain their permission bits; works
    on BSD/macOS `cp`.

- [ ] **Task 7: Move `run_harness.sh` into the workspace**
  - **Description:** `mv "$workdir/.sandbox/run_harness.sh" "$workdir/run_harness.sh"`. Then
    re-assert that `$workdir/run_harness.sh` and `$workdir/.sandbox/start.sh` are executable —
    a cheap post-condition on the copy, since the *template's* bits were already validated in
    Task 4 (R2-1). A failure here means `cp -R` did not preserve modes; `die 7` naming the
    template path.
    Safety of the `mv` is established by Task 2, which exits on every non-"absent" state of
    `$workdir/run_harness.sh` — including the non-regular-file case (exit 9). This branch is
    reached only when nothing exists at that path (Q19).
  - **Review Criteria:** No existing workspace file or directory can be clobbered or written
    into by the `mv`; the post-condition cannot fire for a template that passed Task 4 unless
    `cp` misbehaved, and if it does the message names the template rather than suggesting a
    pointless `chmod` on a file about to be regenerated.

- [ ] **Task 8: Generate `.sandbox/defaults.sh` (only if absent)**
  - **Description:** If `$workdir/.sandbox/defaults.sh` already exists (shipped by a
    harness-specific template, Q8), leave it untouched and log that it was preserved.
    Otherwise write exactly:
    ```bash
    # generated by nono-here.sh
    SANDBOX_COMMAND="claude"
    SANDBOX_COMMAND_DEFAULTS=()
    ```
    with `claude` replaced by the selected harness. Use an **unquoted** heredoc (`<<EOF`) so
    `$harness` interpolates. No other token in the body is subject to expansion — in
    particular `SANDBOX_COMMAND_DEFAULTS=()` contains no `$`, `` ` `` or `\` and needs no
    escaping (R2-4). (The earlier `<<'EOF'` instruction was self-contradictory: a quoted
    heredoc cannot interpolate; S10.) The harness value is constrained to the closed
    `HARNESSES` list, so no injection surface exists. Omit the shebang — the file is only ever
    sourced by `run_harness.sh`, never executed (R2-8); keep the
    `# generated by nono-here.sh` provenance comment.
  - **Review Criteria:** Sourcing the generated file under `set -u` on Bash 3.2 is clean;
    `SANDBOX_COMMAND` matches the selected harness exactly and is quoted;
    `SANDBOX_COMMAND_DEFAULTS=()` appears verbatim; a template-provided `defaults.sh` survives
    byte-for-byte and the preservation is logged.

- [ ] **Task 9: `handover()` — the single exec site**
  - **Description:** Define one function used by both Task 2 and the end of provisioning:
    ```bash
    handover() { cd "$workdir" || die 1 "cannot enter $workdir"; exec ./run_harness.sh "$@"; }
    ```
    Both call sites invoke `handover "$@"`. This resolves the Task 2/Task 9 contradiction the
    reviewer flagged (B5): the working directory is always `$workdir` and the invocation form
    is always identical. DRY — the repo already carries a duplicated workdir idiom; do not add
    a second duplication.
  - **Review Criteria:** Exactly one `exec` appears in the script; provisioning path and fast
    path are indistinguishable in argument handling and working directory; verified by the
    argv-recording stub receiving identical output for both paths.

- [ ] **Task 10: Fix the `set -u` empty-array handling in `templates/default/run_harness.sh`**
  - **Description:** Two related defects. (a) The normalisation line
    `SANDBOX_COMMAND_DEFAULTS=("${SANDBOX_COMMAND_DEFAULTS[@]:-}")` expands an *empty* array to
    a single empty-string element, which the flag-heuristic then prepends as a bogus empty
    argv to the harness. (b) Under `set -u`, `"${arr[@]}"` on an empty array is an unbound-
    variable error in Bash < 4.4 — and macOS ships Bash 3.2, so any naive rewrite crashes on
    the primary target platform.
    Fix: **delete the normalisation line entirely** and guard at the single use site. Note
    that the existing condition dereferences `"$1"` after `$# -eq 0` short-circuits — correct
    today, but the `||` order must be preserved, and the subsequent `if [[ "$1" == …` on the
    `SANDBOX_COMMAND` shift line has no such guard and *is* unbound under `set -u` when the
    defaults array is empty and no args were given (B2). Both sites must use `${1:-}`:
    ```bash
    if [[ $# -eq 0 || "${1:-}" == -* ]]; then
      set -- ${SANDBOX_COMMAND_DEFAULTS[@]+"${SANDBOX_COMMAND_DEFAULTS[@]}"} "$@"
    fi

    if [[ "${1:-}" == "$SANDBOX_COMMAND" ]]; then
      shift
    fi
    ```
    The `${arr[@]+…}` form expands to nothing when the array is empty or unset and is safe on
    Bash 3.2. Do not re-assign the array — that reintroduces (b). Also replace the bare
    `.sandbox/start.sh` invocation with `"$WORKSPACE/.sandbox/start.sh"` so the script does not
    silently depend on the caller's CWD. Bump the `# VERSION` marker.
  - **Review Criteria:** Verified on Bash 3.2 (`/bin/bash` on macOS) *and* Bash 5: with
    `SANDBOX_COMMAND_DEFAULTS=()` and no args, exactly one argument (`$SANDBOX_COMMAND`)
    reaches `start.sh`; with the variable entirely unset, likewise no crash; with populated
    defaults and a flag-only invocation, defaults are prepended in order; invoking from a
    subdirectory still finds `start.sh`.

- [ ] **Task 11: Test suite `nono/test_nono_here.sh`**
  - **Description:** Plain-Bash harness (Q20b). Each case runs in a `mktemp -d` fixture with
    overridden `HOME` and `NONO_HERE_HOME`. Fixture templates contain a `start.sh` that
    records its argv to a file instead of invoking `nono`, and (for fast-path cases) a
    pre-placed workspace `run_harness.sh` stub that does the same. Note that `start.sh` is
    always invoked by absolute path, never resolved through `PATH`, so `PATH` stubbing is not
    used (S11). All provisioning cases run non-interactively via `NONO_HERE_HARNESS` — the
    same code path users get, with no test-only branches in the script. Cases:
    (1) fast path execs existing `run_harness.sh` with args forwarded verbatim, including an
    arg containing a space; (2) non-executable `run_harness.sh` ⇒ exit 2;
    (3) missing/non-executable `start.sh` ⇒ exit 3; (4) non-TTY with no override ⇒ exit 4;
    (5) invalid `NONO_HERE_HARNESS` ⇒ exit 8, no prompt, nothing written;
    (6) template precedence — all four positions, asserted by a marker file per template;
    (7) no template ⇒ exit 5 and all four paths present in stderr;
    (8) malformed template ⇒ exit 7, and a pre-existing `.sandbox` is still intact afterwards
    (regression test for the B1/R2-1 ordering fix). Three sub-cases: template missing
    `run_harness.sh`; template missing `start.sh`; template whose `start.sh` is present but
    not executable;
    (9) stale `.sandbox` in a non-TTY run ⇒ exit 6, directory untouched;
    (10) stale `.sandbox`, `y` piped on stdin with a TTY unavailable ⇒ still exit 6 (proves
    the deletion cannot be driven by a pipe);
    (11) generated `defaults.sh` content matches the selected harness;
    (12) template-provided `defaults.sh` preserved verbatim;
    (13) `run_harness.sh` argv correctness with empty, unset and populated
    `SANDBOX_COMMAND_DEFAULTS`, executed under both `/bin/bash` (3.2) and any newer `bash` on
    `PATH` (regression test for Task 10);
    (14) `NONO_HERE_HOME` derived correctly when invoked through a symlink;
    (15) workdir is the git root when run from a nested subdirectory;
    (16) workspace `run_harness.sh` is a *directory* ⇒ exit 9, and nothing is moved into it.
    The interactive `select` menu itself is covered by cases 4 and 5 (its guards) and is
    otherwise verified manually — it is a thin wrapper over the same selection variable the
    override sets.
  - **Review Criteria:** Suite is self-contained, leaves no artefacts outside `mktemp`, never
    touches the real `$HOME`, exits non-zero on any failure, and prints a per-case pass/fail
    line. Every deliberately raised exit code in the map (2–10) is covered by at least one
    case; exit 1 is excluded as it denotes an unexpected internal failure (S9), and exit 10
    (Ctrl-D) is excluded as it requires a real TTY and is verified manually. No production
    code path exists solely to serve the tests.

## Edge Case & Safety Checklist

- Invoked outside any git repository ⇒ workdir is `$PWD`; inside a subdirectory ⇒ git root.
  Submodule and bare-repo quirks are accepted (Q17), mitigated by printing the resolved
  workdir before provisioning.
- Invoked through a symlink from `~/bin` ⇒ `NONO_HERE_HOME` still resolves to the real
  template root; an explicit `NONO_HERE_HOME` always wins.
- `run_harness.sh` path exists but is a directory, dangling symlink or other non-regular file
  ⇒ exit 9 in Task 2, before any `mv` could write *into* it.
- `run_harness.sh` exists but lacks `+x` ⇒ exit 2, never a silent `bash run_harness.sh`.
- `.sandbox/start.sh` missing or lacking `+x` ⇒ exit 3 on the fast path (workspace defect),
  exit 7 after a fresh copy (template defect).
- `.sandbox` exists without `run_harness.sh` ⇒ confirmation prompt; declining is a clean,
  non-destructive exit 6.
- `rm -r` is used without `-f`; a write-protected or busy `.sandbox` fails loudly.
- stdin not a TTY (CI, pipe) and no `NONO_HERE_HARNESS` ⇒ exit 4 before any write.
- `NONO_HERE_HARNESS` set to an unknown value ⇒ exit 8, never a silent fallback to the menu.
- Non-interactive run encountering a stale `.sandbox` ⇒ exit 6 without deleting; destructive
  actions always require a human at a TTY.
- Ctrl-D at the `select` prompt ⇒ exit 10, never a defaulted harness.
- Garbage or out-of-range `select` input ⇒ re-prompt, never fall through.
- No template directory found ⇒ exit 5 with all four probed paths printed in order.
- Template lacking `run_harness.sh` or `start.sh`, **or shipping them without `+x`** ⇒ exit 7
  in Task 4, before any file is copied or deleted, so no partial `.sandbox` is left behind and
  no existing one is destroyed.
- Empty **or unset** `SANDBOX_COMMAND_DEFAULTS` under `set -u` ⇒ must neither inject an empty
  argv nor crash on Bash 3.2 (Task 10).
- Template ships its own `defaults.sh` ⇒ preserved and the preservation is logged.
- Template contains dotfiles ⇒ `cp -R "$src/."` guarantees they are copied.
- Arguments containing spaces, globs or leading dashes ⇒ forwarded verbatim through `"$@"`.
- The script never writes to the workspace `.gitignore`; `.sandbox/` and `run_harness.sh` are
  meant to be committed (Q10).
- Partial-failure exposure: a failure between copy (Task 6) and `defaults.sh` (Task 8) leaves a
  `.sandbox` without `run_harness.sh` — precisely the state **Task 5** detects and offers to
  repair on the next run. This is intentional and self-healing; say so in the prompt text.

## Review Log (Plan Review)

- **Round 1:** CHANGES REQUESTED. 5 blockers, 7 should-fix, 4 nits.
  - **B1** Q15's order (prompt → template resolution) destroys `.sandbox` before the template
    is validated; contradicts Task 5 and checklist L227. Reorder: selection → resolution +
    validation → prompt → rm → copy.
  - **B2** Task 10's fix leaves `$# == 0`, so `run_harness.sh` L26 `"$1"` is unbound under
    `set -u`. Must also guard L26 (`${1:-}`). Test case (11) currently cannot pass.
  - **B3** Task 11 cases 5/8/9/10 require provisioning, which Q5 gates behind a TTY; the
    "test-only hook" is undefined and contradicts Q6. Choose: (a) add `--harness` /
    `NONO_HERE_HARNESS` non-interactive path (recommended, also fixes CI usability), or
    (b) make the script sourceable and unit-test the functions. `script -q` is not portable.
  - **B4** Task 7's "guaranteed safe by Task 2" is false for a *directory* named
    `run_harness.sh` (Task 2 gates on `-f`); `mv` would move the file inside it. Add exit
    code 8 (not a regular file) and check in Task 2.
  - **B5** Task 2 (`exec "$workdir/run_harness.sh"`) vs Task 9 (`cd` + `exec ./run_harness.sh`)
    contradict, while Task 9 claims a single `exec` site. Unify in `handover()`.
  - **S6** Task 4's `select` premise is inverted: on bad input the *result variable* is empty,
    `$REPLY` holds the raw input.
  - **S7** EOF at the `select` prompt has no assigned exit code.
  - **S8** Exit codes 2/3 overloaded between user-fixable and template-broken causes.
  - **S9** Exit code 1 has no trigger; Task 11's coverage criterion is unsatisfiable.
  - **S10** Task 8: `<<'EOF'` cannot interpolate `$harness`. Instruction is self-contradictory.
  - **S11** Task 11 fixtures: `start.sh` is called by absolute path, never via `PATH`; the
    fast-path case needs a stub `run_harness.sh`.
  - **S12** Task 12 (`PROJECT_MAP.md`) belongs to the Chronicler per AGENTS.md §7. Remove.
  - **N13** Fast path should not echo the workdir on every invocation.
  - **N14** Specify `read -r` in Task 3.
  - **N15** Q8's preserve-and-log branch is YAGNI; no harness-specific template exists.
  - **N16** Task 10 makes the `git rev-parse` idiom a third duplicate; note it as accepted.
  - **Planner resolution (all items):** B1 fixed — Tasks 3–5 reordered so selection and
    template validation precede any deletion; test case 8 added as a regression guard.
    B2 fixed — normalisation line deleted, use-site `${arr[@]+…}` guard, plus `${1:-}` on
    *both* dereference sites; Bash 3.2 and Bash 5 added to the review criteria.
    B3 escalated to the user, who reinstated `NONO_HERE_HARNESS` (Q22a); the test-only hook is
    removed and Task 11 now exercises the shipped path.
    B4 fixed — Task 2 gains an explicit non-regular-file branch (new exit 9) covering the
    directory case; Task 7's safety claim rewritten to reference it.
    B5 fixed — single `handover()` function, `cd "$workdir" && exec ./run_harness.sh "$@"`,
    called from both sites.
    S6 fixed (`$harness` empty / `$REPLY` raw — inversion corrected). S7 fixed (exit 10).
    S8 fixed (2/3 = workspace defect, 7 = template defect; documented under the map).
    S9 fixed (exit 1 redefined as unexpected-internal-only and excluded from coverage).
    S10 fixed (unquoted heredoc, contradiction removed). S11 fixed (no `PATH` stubbing;
    absolute-path invocation noted, fast-path stub added). S12 fixed (Task 12 removed).
    N13 fixed (workdir echoed only when provisioning). N14 fixed (`read -r`).
    N15 **rejected** — the preserve-existing-`defaults.sh` branch is a user decision (Q8) and
    the documented extension point for harness-specific templates; it is three lines and
    removing it would make per-harness templates unable to ship defaults.
    N16 accepted and recorded inline in Task 1.
- **Round 2:** CHANGES REQUESTED. 1 blocker, 3 should-fix, 4 nits.
  Round 1 verification: B2, B3, B4, B5, S6–S12, N13, N14, N16 confirmed resolved in the body,
  not merely in the log. N15 rejection accepted. B1 only **partially** resolved — see R2-1.
  New-defect checks that came back clean: exit codes 8/9/10 are internally consistent and each
  is reachable exactly once; the Task 3→4→5 reorder introduces no unreachable branch;
  `handover()` unification removes the last duplicate `exec`; Task 10's snippet is correct on
  Bash 3.2 (`${arr[@]+"${arr[@]}"}` expands to nothing for empty *and* unset arrays there, the
  `||` short-circuit order is preserved, and with empty defaults + no args exactly one argv
  reaches `start.sh`).
  - **R2-1 BLOCKER** — B1 not fully closed. Task 4 validates only the *presence* of
    `run_harness.sh` and `start.sh` in the template; the `+x` check lives in Task 7, i.e.
    *after* Task 5's `rm -r "$workdir/.sandbox"`. A template whose mode bits were dropped (zip,
    `cp` without `-p`, checkout on a noexec mount — the exact scenario Task 7 itself cites)
    therefore passes Task 4, the user's existing `.sandbox` is deleted, and the run then aborts
    with exit 7, leaving neither a sandbox nor a harness. Move the executable-bit assertion
    into Task 4 (validate the template in place, before any destructive step). Task 7's
    post-copy check may stay as a cheap post-condition, but it must not be the first line of
    defence. Extend Task 11 case (8) to cover a template with a non-executable `start.sh`.
  - **R2-2 SHOULD** — Task 11 carries two `Review Criteria` blocks (L272–276 and L277–279).
    The second is the pre-S9 text and reinstates the unsatisfiable "every exit code in the map
    is covered" claim, contradicting the first. Delete L277–279.
  - **R2-3 SHOULD** — Checklist L313–315 still says the incomplete-`.sandbox` state is "the
    state Task 3 detects". After the reorder that is Task 5. Stale cross-reference introduced
    by the B1 edit.
  - **R2-4 SHOULD** — Task 8's heredoc rationale is still muddled: "escape the only other
    `$`-bearing token by writing the array line literally" — there is no other `$`-bearing
    token in the block. Reduce to a plain instruction: unquoted `<<EOF`, `$harness` is the sole
    expansion, no escaping required. Ambiguous prose here is what produced S10.
  - **R2-5 NIT** — `handover()`: a failing `cd` returns non-zero and surfaces as exit 1, which
    the map declares is "never raised deliberately". Use `cd "$workdir" || die <code> …`.
  - **R2-6 NIT** — Task 5 cites "(S14)" for `read -r`; the item is N14.
  - **R2-7 NIT** — Checklist bullets L305–306 and L310 both cover empty
    `SANDBOX_COMMAND_DEFAULTS`. Drop L310.
  - **R2-8 NIT** — The generated `defaults.sh` gets a shebang but is only ever sourced. Harmless;
    keep it only if the template's own `defaults.sh` does the same, for consistency.
  - **Planner resolution (all items):** R2-1 fixed — the `+x` assertion moved into Task 4, so
    the template is fully validated in place before Task 5 can delete anything; Task 7 retains
    it only as a post-copy post-condition, and Task 11 case (8) is extended to a template with
    a non-executable `start.sh` asserting the existing `.sandbox` survives.
    R2-2 fixed (duplicate `Review Criteria` block deleted). R2-3 fixed (cross-reference now
    Task 5). R2-4 fixed (heredoc instruction reduced to: unquoted `<<EOF`, `$harness` the sole
    expansion, no escaping). R2-5 fixed (`cd "$workdir" || die 1 …`, and exit 1's map entry
    now names this case). R2-6 fixed (N14). R2-7 fixed (duplicate bullet dropped).
    R2-8 fixed — shebang removed; the file is only sourced, and the template ships no
    `defaults.sh` to be consistent with.
- **Round 3:** **APPROVED.** Verification of R2-1…R2-8 in the plan body (not merely the log):
  R2-1 closed — Task 4 now asserts presence *and* `+x` on the template's `run_harness.sh` and
  `start.sh` before any destructive step; Task 5 is explicitly gated on a validated template;
  Task 7 is demoted to a post-copy post-condition naming the template; Task 11 case (8) has
  the three sub-cases including non-executable `start.sh` with a surviving `.sandbox`.
  R2-2 closed (single `Review Criteria` block in Task 11). R2-3 closed (checklist now cites
  Task 5). R2-4 closed (unquoted `<<EOF`, `$harness` sole expansion, no escaping required).
  R2-5 closed (`cd "$workdir" || die 1 …`; exit 1's map entry names the case).
  R2-6 closed (N14). R2-7 closed (single empty/unset-defaults bullet). R2-8 closed (no shebang).
  No new defects: control flow Task 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 is total, every exit code
  2–10 is raised at exactly one site, `handover()` remains the single `exec`, and Task 10's
  snippet stays Bash 3.2-safe.
  Remaining non-blocking note: Task 11's criterion "every code 2–10 is covered" holds for all
  codes except 10 (EOF at `select`), which the task text consciously defers to manual
  verification. Either add a case or reword the criterion — implementer's choice.
  No BLOCKERs. Builder may proceed.

## Final Status (Code Review)

- **Round 1:** N/A
- **Round 2:** N/A
- **Round 3:** N/A
