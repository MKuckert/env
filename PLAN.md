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
defect (including missing exec bits detected after the copy in Task 7).


## Implementation Steps

> Status Markers: [ ] Open, [/] In Progress, [x] Completed (set after accepted review only!)

- [x] **Task 1: Script skeleton, self-location and workdir resolution**
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

- [x] **Task 2: Fast path — hand over to an existing `run_harness.sh`**
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

- [x] **Task 3: Harness selection**
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

- [x] **Task 4: Template resolution and validation**
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


- [x] **Task 5: Stale `.sandbox` handling**
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

- [x] **Task 6: Copy template to `.sandbox`**
  - **Description:** `mkdir -p "$workdir/.sandbox"` then `cp -R "$template/." "$workdir/.sandbox/"`
    so dotfiles (`.gitignore`) and modes are preserved without `rsync`.
    **Added at Task 5 code review (T5-S1):** guard the non-directory `.sandbox` case before the
    `mkdir -p`. Task 5's `[[ -e … ]]` test is false for a *dangling symlink* at
    `$workdir/.sandbox`, so that path reaches here untouched and `mkdir -p` fails with
    `File exists` / `Not a directory`, aborting via `set -e` as a bare exit 1 whose message does
    not name the real cause. Mirror Task 2's precedent: test
    `[[ -e "$workdir/.sandbox" || -L "$workdir/.sandbox" ]] && [[ ! -d "$workdir/.sandbox" ]]`
    ⇒ `die 9` naming the path as existing but not a directory (reusing code 9, whose meaning is
    "path exists but is not the expected file type"). The `|| -L` is what makes the guard fire at
    all, and the dangling symlink is the *only* case that reaches it: every other pre-existing
    `.sandbox` — regular file, socket, symlink to either, symlink to a directory — passes Task 5's
    `[[ -e … ]]` test and is intercepted there with exit 6 (or, on an interactive `y`, removed by
    its `rm -r`). Verified by test at Task 6 code review; an earlier draft of this task wrongly
    claimed the guard also caught regular files and sockets.
  - **Review Criteria:** `.gitignore`, `hooks/`, `profile.template.json`, `start.sh` all
    present afterwards; `start.sh` and the hook templates retain their permission bits; works
    on BSD/macOS `cp`; a dangling-symlink `.sandbox` exits 9 with a message naming the path,
    never a bare exit 1 from `mkdir`.

- [x] **Task 7: Move `run_harness.sh` into the workspace**
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

- [x] **Task 8: Generate `.sandbox/defaults.sh` (only if absent)**
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

- [x] **Task 8b: Wire the provisioning handover**
  - **Depends On:** Tasks 8, 9. **Owned Paths:** `nono/nono-here.sh`. **Parallel Safe:** yes,
    with Task 10 only (disjoint paths).
  - **Description:** Added at Task 8 code review. The plan's decomposition left this call
    unowned: Task 8 ends at `defaults.sh` and Task 9 was deliberately approved
    definition-only, so the provisioning path currently falls off the end of the script and
    exits 0 **without ever exec'ing**. That contradicts Q4 ("after provisioning, exec
    `run_harness.sh` immediately"), Q15's ordering, and Task 9's own criterion that the
    provisioning and fast paths be indistinguishable. Effect today: a cold repository is fully
    provisioned and then exits instead of launching the harness; only a *second* invocation
    works, via the Task 2 fast path.
    Fix: call `handover "$@"` at **top level, after the Task 8 preserve/generate `if/else`**,
    so both branches reach it. Do not add a second `exec` — reuse the existing `handover()`
    from Task 9, which already performs `cd "$workdir"` and `exec ./run_harness.sh "$@"`.
  - **Review Criteria:** `exec` still appears exactly once in the script; an argv-recording
    stub receives byte-identical argv and `$PWD` from the provisioning path and the fast path
    (Task 9's deferred criterion, now finally testable against two real call sites); a cold
    workspace is provisioned **and** handed over in a single invocation; arguments containing
    spaces and leading dashes survive; the fast path is unchanged.

- [x] **Task 9: `handover()` — the single exec site**
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

- [x] **Task 10: Fix the `set -u` empty-array handling in `templates/default/run_harness.sh`**
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
- `.sandbox` is a **dangling symlink** ⇒ exit 9 in Task 6, before `mkdir -p` could abort as an
  unexplained exit 1. This is the only case that reaches the Task 6 guard: a dangling symlink is
  invisible to Task 5's `-e` test. Every other non-directory at that path (regular file, socket,
  symlink to either) passes `-e` and is intercepted by **Task 5 with exit 6**, not exit 9.
  A symlink *to* a directory is likewise handled by Task 5; on an interactive `y` its `rm -r`
  unlinks the symlink and `mkdir -p` then creates a new real directory, so the former target's
  contents survive on disk but are left orphaned.
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

- **Task 1 — Round 1: APPROVED.** 0 blockers, 0 should-fix, 3 nits.
  All four review criteria met: symlink-invoked `NONO_HERE_HOME` resolves via the portable
  `while [[ -L ]]` loop with `cd -P` (handles absolute targets, relative targets and symlinked
  path components); `${NONO_HERE_HOME:-$script_dir}` lets an explicit export win;
  `git rev-parse --show-toplevel 2>/dev/null || echo "$PWD"` is `set -e`-safe and yields the
  git root or `$PWD`; the fast path emits nothing. `#!/usr/bin/env bash`, `set -euo pipefail`,
  `# VERSION 2`, `SELF` and `die <code> <msg…>` (stderr, `$SELF`-prefixed, exits with `$1`) all
  present. No `readlink -f`/`realpath`; Bash 3.2-safe. No speculative code for Tasks 2–11 —
  only the N13 contract comment. Fail Loud respected: the sole `2>/dev/null` is the
  plan-sanctioned not-a-repo probe with a documented explicit fallback.
  Nits (non-blocking, no rework required): (1) `NONO_HERE_HOME` is assigned, not exported —
  correct for Task 4's in-script use, becomes a defect only if a later task expects a child
  process to see it; (2) the symlink loop has no cycle guard, so a self-referential symlink
  hangs rather than failing loud — accepted as the plan's idiom, worth a bounded loop if this
  block is touched again; (3) `src`/`dir`/`target` leak as top-level globals — guard against
  reuse of those scratch names in later tasks.
- **Task 9 — Round 1: APPROVED.** 0 blockers, 0 should-fix, 3 nits.
  Implemented verbatim as the plan mandates: `handover() { cd "$workdir" || die 1 …; exec
  ./run_harness.sh "$@"; }`. Exactly one `exec` in the script. Definition-only scope is correct
  — Task 2 owns the fast-path call site and provisioning is unimplemented; no speculative call
  site was invented.
  (a) `$workdir` read from enclosing scope is safe: line 45 assigns it unconditionally at top
  level, before any code that could reach `handover`, and the `git rev-parse … || echo "$PWD"`
  form always yields a value, so `set -u` cannot fire. `handover` is a plain function, not a
  subshell, so `die`'s `exit` terminates the script as intended.
  (b) `exec ./run_harness.sh` is correct per B5: the `./` prefix means `PATH` is never
  consulted, and the preceding `cd` guarantees the CWD is `$workdir` on both paths, so the two
  call sites will be indistinguishable in both argv and CWD once Task 2 lands. `$workdir` is
  quoted, so spaces and globs are inert. `CDPATH` cannot interfere: it is consulted only for
  operands not beginning with `/`, `./` or `../`, and both `git rev-parse --show-toplevel` and
  `$PWD` are absolute — for the same reason the CDPATH stdout-echo side effect cannot fire.
  (c) `die 1 "cannot enter $workdir"` matches the exit-1 map entry and closes R2-5; the message
  names the offending path (Fail Loud).
  Bash 3.2-safe (no `${arr[@]+…}`, no `local -n`, no `mapfile`). Shebang, `set -euo pipefail`
  and `# VERSION 2` retained.
  Nits (non-blocking): (1) `cd "$workdir"` would misparse a `$workdir` with a leading dash as
  options; unreachable today since both sources are absolute, but `cd -- "$workdir"` is free
  insurance; (2) if `exec` itself fails (missing/non-executable target) the script dies with
  126/127 and no `$SELF`-prefixed message — acceptable only because Task 2 pre-checks `-x`, so
  that guard must not be dropped; (3) the "both paths identical" criterion is discharged only
  by construction here — re-verify with the argv-recording stub against *both* real call sites
  when Task 2 and Task 7/8 land.
- **Task 2 — Round 1: APPROVED.** 0 blockers, 0 should-fix, 3 nits.
  All four review criteria met. Branch ladder is total and mutually exclusive, and branch 1
  fires before any `-f` test, so no non-regular file can reach Task 7's future `mv`.
  `[[ -e P || -L P ]] && [[ ! -f P ]]` verified for: directory (`-e` true, `-f` false ⇒ 9);
  dangling symlink (`-e` false, `-L` true ⇒ 9 — the `|| -L` disjunct is load-bearing exactly
  here); symlink-to-directory (⇒ 9); socket/FIFO (⇒ 9). A symlink to a regular executable file
  correctly falls through to the exec branch, since the contract is "regular file" and
  `-f`/`-x` follow symlinks.
  (b-i) The absent explicit `exit 0` is correct: a Bash `if` with a false condition and no
  `else` returns 0, and the condition context does not trip `set -e`. Keeping it out makes the
  Tasks 3–8 append a pure addition rather than an edit; adding it now would be speculative.
  (b-ii) The single `-x` check on `.sandbox/start.sh` conflating "missing" and "not executable"
  is acceptable — the exit-code map itself defines code 3 as covering both, and the message
  reproduces that wording rather than asserting an untested state while naming the exact path.
  (c) The `-x` pre-check gating `handover` is present and load-bearing; it discharges Task 9's
  nit (2) (`exec` dying 126/127 with no `$SELF` message). Must not be dropped.
  (d) Fast path performs no writes, deletions or prompts and is silent on success (N13); all
  output is stderr via `die`. `exec` count still exactly 1.
  Bash 3.2-safe (only `[[ ]]`, no arrays, no `${arr[@]+…}`). Preamble, `# VERSION 2` and the
  bare `script_dir="$(resolve_script_dir)"` assignment with its Fail-Loud comment undisturbed.
  No speculative code beyond the Task 3–8 marker comment. Fail Loud respected throughout.
  Nits (non-blocking): (1) `-f` is re-tested in branches 2 and 3 although branch 1 already
  established regular-file-ness — explicit and harmless; (2) the exit-3 message offers a
  `chmod +x` hint that fixes only one of the two states it covers — split it if the block is
  ever touched; (3) `-x "$workdir/.sandbox/start.sh"` is also true for an executable directory
  at that path, which would then fail loudly inside `run_harness.sh`.
- **Task 3 — Round 1: APPROVED.** 0 blockers, 2 should-fix (both deferred to later tasks), 4 nits.
  All six review criteria met, validated on a real PTY (`pty.fork()`) — including exit 10 on
  Ctrl-D, which the plan's Round 3 note had deferred to manual verification. That note is now
  discharged empirically.
  Extension point: `HARNESSES` is declared once (L9) above `die`, and both consumers plus both
  error messages derive from it — no count, index or hardcoded harness name elsewhere. Adding a
  harness is genuinely a one-token edit.
  (a) Invalid override can never reach the menu: `die 8` sits inside the
  `[[ -n "${NONO_HERE_HARNESS:-}" ]]` branch, so entering that branch is irrevocable and the
  `elif`/`else` are structurally unreachable. Fail Loud by construction, not by convention.
  `NONO_HERE_HARNESS=""` correctly falls to exit 4, not 8, matching the plan's "set *and
  non-empty*" wording and yielding the actionable message.
  (b) Empty-line input at the `select` prompt redisplays the menu with no warning. Assessed as
  correct and unavoidable bash semantics, not a gap: `select` re-displays the words and prompt
  and *skips the loop body entirely* when the line read is empty, so no user code can run. The
  criterion "invalid menu input re-prompts" and the checklist's "never fall through" both hold;
  the Description's "warning whenever `$harness` is empty" describes the loop body, not an input
  that never enters it. Emitting a warning here would require abandoning `select`, which Q5
  mandates. Non-empty invalid input (`99`, `garbage`) does warn, naming the raw `$REPLY`.
  (c) `set -u` safe: both reads of `harness` are guarded (`${harness:-}`, L93/L98); `$REPLY`
  cannot be unbound because the body runs only after a non-empty line was read, and that read is
  what assigns `REPLY`. The in-loop `${harness:-}` guard is redundant (`select` always assigns
  the result variable before the body) but correct and cheap — keep it. The post-loop check at
  L98 is the only thing between EOF and a defaulted harness, and it dies.
  (d) Filesystem purity accepted **for these fixtures only**: the `find` path-listing diff is
  weaker than a checksum, but the fixtures held no non-`.git` files, so in-place mutation had no
  possible target and creation/deletion is exactly what listing equality detects. Evidence is
  complete here, inadequate from Task 5 onward — see S2.
  Bash 3.2-safe (`[[ ]]`, plain array expansion, `select`, `PS3`; no `${arr[@]+…}` needed since
  `HARNESSES` is never empty). `${HARNESSES[*]}` is the correct choice over `[@]` for a
  human-readable value list and is safe inside `die`'s `$*`. Preamble, `# VERSION 2`, the bare
  `script_dir="$(resolve_script_dir)"` and its Fail-Loud comment undisturbed; `exec` count still
  exactly 1; no speculative Task 4–8 code beyond the marker comment.
  Should-fix (deferred, not Task 3 rework): (S1) the resolved workdir is still not echoed before
  the menu — Q17/N13 require it "before acting", the L51 comment defers it to "Task 2+" and no
  task now owns it, so the user picks a harness without seeing which directory is about to be
  provisioned. Assign to Task 4 alongside the template-path banner. (S2) purity assertions must
  switch from `find` path-listing to content digests before Task 5 lands, since Task 5's own
  criterion is "byte-for-byte untouched" and Task 11 cases 9/10 will have fixtures with content.
  Nits (non-blocking): (1) loop variable `h` leaks as a global, joining `src`/`dir`/`target` from
  Task 1 — harmless (dead after a straight-line branch) but the leak set is now four names;
  (2) `PS3` is set globally and never restored — irrelevant before an `exec`, but a second global
  side effect in the same block; (3) if this block is ever touched, `PS3` could carry the choose-
  a-number hint for the empty-line case — do not restructure `select` to chase it; (4) both
  error messages render the list identically via `${HARNESSES[*]}`, so no drift is possible.
- **Task 4 — Round 1: APPROVED.** 0 blockers, 1 should-fix, 4 nits.
  All three review criteria met. Probe order (L107–111) is exactly user-harness → user-default →
  bundled-harness → bundled-default, first-existing-wins via `break`; verified across all four
  stages with `NONO_HERE_HARNESS=copilot` so `$harness` interpolation was genuinely exercised.
  An existing-but-invalid template dir wins the probe and then fails validation (exit 7) rather
  than falling through to a valid candidate behind it — the correct reading of Q9: precedence is
  about *location*, not scavenging for the first working template. `die 5` prints all four paths
  in probe order, one per line, harness interpolated, matching the actually-probed values.
  **R2-1 closed in place.** Both the presence check (L130) and the `+x` check (L133) live in
  Task 4, ahead of every Task 5–8 site; the only statements between harness selection and
  validation are `-d` tests and two stderr echoes. Discharged empirically, not by construction:
  exit 7 with a pre-existing `.sandbox` leaves it byte-identical (`shasum` 9aa42988… before and
  after) — a content digest, closing Task 3's S2. All four exit-7 sub-cases (missing/non-`+x`
  `run_harness.sh` and `start.sh`) name both the template path and the offending file.
  (a) DRY: the four candidate paths appear twice (probe loop and `die 5` body). Assessed as
  *not* the N16 case — N16 accepted a behavioural idiom duplicated across files that must stay
  independently executable, whereas this is data duplicated twice inside one straight-line
  block, removable with a single Bash 3.2-safe array. See S3.
  (b) `die 5`'s single multi-line string leaves continuation lines unprefixed. Accepted as the
  better presentation: the paths stay copy-pasteable.
  (c) `${HOME:-}` degrading candidates 1–2 to `/.nono-here/templates/…` is harmless — a `-d`
  test on a non-existent root-level path, and even a contrived match yields only a read.
  `env -u HOME` exits 0 with no `set -u` crash.
  (d) The N13/Q17 workdir echo (L126) is correctly placed: every earlier exit precedes it and
  the fast path `exec`s at L70, so the fast path stays silent; `exec` count still exactly 1.
  (e) Zero filesystem mutation in L103–136 (only `-d`/`-f`/`-x` tests and stderr echoes), and
  `$template` is left as the absolute path of a directory with both required files present and
  executable — exactly Task 5's stated precondition.
  Bash 3.2-safe; preamble, `# VERSION 2` and the bare `script_dir="$(resolve_script_dir)"` with
  its Fail-Loud comment undisturbed; no speculative Task 5–8 code; no fallback and no
  `2>/dev/null` — Fail Loud respected.
  Should-fix: (S3) build the four candidates once into an array and reuse it for both the probe
  and the `die 5` message (`printf '%s\n' "${candidates[@]}"`; the array is never empty, so no
  `${arr[@]+…}` guard is needed). Non-blocking for Task 5, but land it before Task 11 case (7)
  hardcodes the current message text and pins the duplication in place.
  Nits (non-blocking): (1) exit 5 fires *before* the workdir echo, so the least-diagnosable
  abort is the one that omits the workdir — move the echo above the probe if the block is
  touched; (2) `candidate` and `required` leak as globals, bringing the leak set to six
  (`src`/`dir`/`target`/`h`/`candidate`/`required`); (3) the template echo precedes validation,
  so a malformed template is announced then rejected — deliberate and better diagnostics, noted
  only; (4) `NONO_HERE_HOME` is now `export`ed (L47), changed since Task 1's review where it was
  assign-only; disclosed by comment and consumed by no child yet, but Task 11's fixtures must
  account for it being inherited.
- **Task 5 — Round 1: APPROVED.** 0 blockers, 1 should-fix (deferred to Task 6), 4 nits.
  All six review criteria met, discharged empirically on a real PTY (`pty.fork()`) under
  `env -i` with a fake `HOME`/`NONO_HERE_HOME`, with purity asserted by content digest as
  Task 3's S2 requires.
  (a) **`-f` criterion confirmed by an exhaustive grep for the bare token**, not just
  `rm`-adjacent forms. Eight matches repo-wide, five in `nono-here.sh`: L19 is the
  `readlink -f` prose comment, and L62/64/66/130 are `[[ -f ]]` regular-file tests. No `-f`
  ever appears as a command flag anywhere in the script. `rm -r` (L158) carries no `-f`, no
  `|| true` and no `2>/dev/null`, so a write-protected or immutable `.sandbox` propagates
  through `set -e` — verified with `chflags uchg`: exit 1, `rm`'s own stderr visible, script
  halted. (The tester's `chmod 500` attempt hanging is a BSD `rm` interactive-prompt artefact,
  not a script defect.)
  (b) Ordering is correct and load-bearing: the `[[ ! -t 0 ]]` guard (L143) precedes the
  warning and the `read` entirely, so a piped `y` exits 6 with the `.sandbox` byte-identical
  and the `y` never even consumed — the strongest form of criterion "a non-TTY run never
  deletes anything". Template validation (L129–136) precedes the whole block, so no path
  reaches the `rm` without `$template` validated for presence *and* `+x` (R2-1 stays closed);
  the block is itself reachable only via Task 2's fall-through, i.e. `run_harness.sh` absent.
  (c) `reply=""` is pre-initialised and `read -r -p … || reply=""` is a `||` list, so `set -e`
  cannot fire on EOF. The clobber is deliberately fail-safe: input terminated by Ctrl-D
  without a newline returns non-zero with `reply` partially assigned, and the `|| reply=""`
  discards it, so a half-typed `y` declines rather than deletes. `case` patterns `y | Y` are
  single literal characters with no glob metacharacter, and `*)` is total — nothing but
  exactly `y`/`Y` can reach the `rm`. Confirmed on a PTY: `y`/`Y` delete; `n`, empty line,
  `yes`, garbage and Ctrl-D all exit 6 with the directory intact by digest.
  (d) Warning is three yellow `\033[33m` stderr lines matching `start.sh`'s convention, naming
  the template, the incomplete state and the self-healing rationale the checklist mandates;
  the prompt matches the plan's string character-for-character. Both exit-6 messages name the
  offending path and the non-TTY one names the manual fix (Fail Loud).
  Bash 3.2-safe (`[[ ]]`, `case`, `read -r -p`, builtin `echo -e`; no `${arr[@]+…}`, no
  `read -t`/`-i`). Preamble, `# VERSION 2` and the bare `script_dir="$(resolve_script_dir)"`
  with its Fail-Loud comment undisturbed; `exec` count still exactly 1; no speculative Task
  6–8 code beyond the marker comment.
  Should-fix (deferred — **not** Task 5 rework): (T5-S1) `[[ -e "$workdir/.sandbox" ]]` is
  false for a *dangling symlink*, so that path skips the whole block. Within Task 5's own
  scope this is harmless and non-destructive — nothing is deleted and no criterion is
  violated — which is why it does not block. But Task 2 deliberately spends an `|| -L`
  disjunct and exit 9 on the identical case for `run_harness.sh`, and here the consequence
  merely moves downstream: Task 6's `mkdir -p` will fail `File exists`/`Not a directory` and
  abort as a bare exit 1 whose message does not explain the cause — a Fail-Loud violation in
  spirit (fails, but not *clearly*). The plan's Edge Case checklist was silent on a
  non-directory `.sandbox`. Fixed at the plan level rather than left in a log: Task 6's
  description now mandates an `-e || -L` / `! -d` guard with `die 9`, its review criteria name
  the case, and a checklist bullet has been added. Guarding in Task 6 is the better site than
  Task 5 — it is where the failure actually occurs, and it also covers a regular file or
  socket at that path, which a Task 5 patch alone would not.
  *[Corrected at Task 6 round 1 — the preceding clause is false and is the origin of T6-B1:
  a regular file or socket at `.sandbox` never reaches Task 6, since Task 5's `-e` is true for
  both. The Task 6 guard's sole reachable case is the dangling symlink. Left as written history;
  see the Task 6 round-1 entry. Do not propagate this clause.]*
  Nits (non-blocking): (1) default `IFS` word-splitting trims surrounding whitespace, so
  `" y "` is accepted as `y` — benign, and tightening it would reject an obviously affirmative
  answer; (2) the ANSI colour is emitted unconditionally, so a run with stdin on a TTY but
  stderr redirected to a file writes raw escape codes into the log — inherited from
  `start.sh`'s convention, worth a `[[ -t 2 ]]` gate only if that block is touched again;
  (3) `reply` leaks as a global, bringing the leak set to seven
  (`src`/`dir`/`target`/`h`/`candidate`/`required`/`reply`); (4) the third warning line is long
  enough to wrap on an 80-column terminal — cosmetic only.
- **Task 6 — Round 1: CHANGES REQUESTED.** 1 blocker, 2 should-fix, 3 nits.
  The **code is functionally correct and every functional criterion is met.** What is rejected
  is the prose shipped *with* it: the guard's comment, Task 6's description and the Edge Case
  checklist all assert coverage that testing disproves. An inaccurate comment asserting
  unreachable coverage is a defect, and this one originated in my own Task 5 log — so it is
  corrected here rather than inherited.
  **Functional verification (accepted):** `bash -n` and `/bin/bash -n` clean; `exec` count still
  exactly 1; bare-`-f` grep still yields only the L19 `readlink -f` prose comment and the
  `[[ -f ]]` tests at L62/64/66/130 — no `-f` as a command flag. Success path exits 0 and
  `.sandbox` holds `.gitignore`, `hooks/{after,before}-template`, `profile.template.json`,
  `run_harness.sh`, `start.sh`, all six digests byte-identical to the template and all four
  executables at `rwxr-xr-x` — discharged against the **real bundled** `templates/default`, not
  only synthetic fixtures, with the repo confirmed unmodified. `mkdir -p` (L176) and `cp -R`
  (L177) carry no `|| true` and no `2>/dev/null`, so both propagate through `set -e`.
  `"$template/."` is preserved verbatim — not `cp -a` (GNU-only), not a glob (would miss
  dotfiles), satisfying Q13 and the dotfile checklist bullet. The T5-S1 regression is genuinely
  fixed: a dangling-symlink `.sandbox` now exits 9 naming the path instead of silently exiting 0.
  Bash 3.2-safe (`[[ ]]` only, no `${arr[@]+…}`). Preamble, `# VERSION 2` and the bare
  `script_dir="$(resolve_script_dir)"` with its Fail-Loud comment undisturbed. No speculative
  Task 7–8 code beyond the marker comment.
  (c) **Confirmed intended, no criterion violated.** A real pre-existing `.sandbox` holding
  unrelated content is removed wholesale by Task 5's `rm -r` on `y`, so `cp -R` never merges
  onto pre-existing content and that merge path is unreachable. This is exactly Q1/Q11/Q18:
  `rm -r` then a fresh copy, no backup directory, gated behind an explicit `y` at a TTY after a
  warning that names the template. Destruction is disclosed and human-confirmed — Fail Loud
  holds.
  - **T6-B1 BLOCKER — the guard's comment (L165–171) overstates its own reach.** L172 is
    reachable **only** for a dangling symlink. A regular file at `.sandbox` exits 6 and a
    symlink-to-a-regular-file exits 6: `[[ -e ]]` (L142) is true for both, so Task 5 intercepts
    them and they never reach L172. The comment's closing clause — that a symlink *to a
    directory* "passes `-d` and is deliberately accepted" — describes behaviour that does not
    occur: Task 5 intercepts it first (exit 6 non-interactively; on `y` the `rm -r` unlinks the
    symlink, orphaning the target's contents, after which `mkdir -p` creates a brand-new **real**
    directory at `.sandbox`). The copy never lands in the symlink's target. Reword L165–171 to
    state only what is true: this guard exists solely for the dangling-symlink case, which is
    invisible to Task 5's `-e` test; every other non-directory at that path is already handled by
    Task 5 with exit 6. Drop the "symlink to a directory is accepted" sentence entirely rather
    than repairing it — the accurate version ("Task 5 deletes the link and a fresh real directory
    replaces it") belongs in Task 5's block, not here. Keep the `|| -L` disjunct: it is
    load-bearing, and it is the *only* reason the guard fires at all.
  - **T6-S1 SHOULD — Task 6's description (L167–175) carries the same error.** Its final
    sentence ("A symlink *to a directory* is deliberately left alone: Task 5 accepts it, and its
    `rm -r` removes only the link, not the target") implies Task 6 sees such a path. It does not.
    Correct it in the plan body, not merely in this log.
  - **T6-S2 SHOULD — Edge Case checklist L314–318 is wrong on two counts.** It claims a
    non-directory `.sandbox` "(dangling symlink, regular file, socket) ⇒ exit 9 in Task 6" —
    regular files and sockets exit **6** in Task 5. Narrow the bullet to the dangling symlink.
    The following sentence ("A symlink *to* a directory is accepted by Task 5, whose `rm -r`
    unlinks the symlink and leaves the target intact") is true as far as it goes but omits the
    consequence that matters: the target is left *orphaned* and provisioning proceeds into a new
    real directory. Say so.
  - Task 6's **Review Criteria** need no change — "a dangling-symlink `.sandbox` exits 9 with a
    message naming the path, never a bare exit 1 from `mkdir`" is precisely and only what the
    implementation delivers.
  Nits (non-blocking): (1) reusing exit code 9 for two distinct paths (`run_harness.sh` in Task 2,
  `.sandbox` here) is sanctioned by the map's "path exists but is not the expected file type"
  wording and both messages name their path, so they stay distinguishable — noted only;
  (2) `cp -R` on a template containing a symlink copies the link, not the target, on BSD `cp`
  (no `-L`); correct and desirable here, but Task 7's `mv` assumes a regular `run_harness.sh`,
  which Task 4's `-f` check already guarantees; (3) the leak set is unchanged at seven — this
  task introduces no new top-level scratch names.
  **Route back to the Builder for the comment and plan-text corrections only. No functional
  rework. Task 6 stays `[ ]`.**
- **Task 6 — Round 2: APPROVED.** All three round-1 findings discharged; Task 6 marked `[x]`.
  **T6-B1 fixed.** The guard's comment (now L165–170) drops the symlink-to-directory claim
  entirely, as directed, rather than repairing it. It now states only that a dangling symlink is
  invisible to Task 5's `-e` test and therefore reaches the guard, and that the alternative is a
  bare `set -e` exit 1 that names no cause. `|| -L` retained at L171 — still load-bearing and
  still the only reason the guard fires.
  **T6-S1 fixed** (by the Operator; no Builder held PLAN.md write access). Task 6's description
  (L174–179) now names `|| -L` as the trigger, states the dangling symlink is the *only* case
  reaching the guard, routes every other form to Task 5 (exit 6, or removed by its `rm -r` on an
  interactive `y` — a branch the script comment elides), and records that an earlier draft wrongly
  claimed regular files and sockets were caught. Review Criteria correctly left untouched.
  **T6-S2 fixed.** Edge Case bullet (L318–324) is narrowed to the dangling symlink as the sole
  exit-9-in-Task-6 case, attributes regular file / socket / symlink-to-either to Task 5 with
  exit 6, and now states the orphaning consequence for an accepted symlink-to-directory.
  **Sweep for surviving instances of the false claim:** exit-code map L60 concerns
  `run_harness.sh` (Task 2's `! -f` guard), where directory / dangling symlink / socket genuinely
  do yield 9 — **unaffected, confirmed correct**. L506–508 likewise describes Task 2's `! -f`
  test, so "symlink-to-directory (⇒ 9); socket/FIFO (⇒ 9)" is accurate there and needs no change.
  L662 (Task 5 round-1 log) *is* a genuine surviving instance and the origin of the defect; as a
  review-log entry it is left as written history but annotated in place with a correction pointer
  so it cannot be propagated. **No normative text anywhere still claims exit 9 for a regular file
  or socket at `.sandbox`.**
  **Verification scope — disclosed limitation:** no shell tool was available to me or the Explorer
  this round, so I could **not** execute `git diff 11e4814` and cannot claim to have machine-verified
  byte-identity of the functional lines. What I did verify by reading the file: the condition
  (L171), `die 9` (L172), `mkdir -p` (L175) and `cp -R "$template/." "$workdir/.sandbox/"` (L176)
  are substantively identical to the text quoted as correct in round 1, and their line numbers have
  shifted by exactly −1, consistent with the comment losing one line and nothing else changing.
  On that basis the round-1 functional validation — success path exit 0 with all files present,
  six digests matching the real bundled `templates/default`, executable bits at `rwxr-xr-x`,
  dangling symlink ⇒ exit 9, `exec` count 1, no bare `-f` flag — is carried forward as still
  standing. **If any functional line did change, this approval does not cover it.**
  Nit (non-blocking, carried): the script comment says other forms are intercepted "with exit 6",
  omitting Task 5's interactive-`y` `rm -r` branch. The load-bearing claim (nothing but a dangling
  symlink reaches the guard) is true, and PLAN.md L177 carries the precise version — not worth a
  third round.
- **Task 7 — Round 1: APPROVED.** 0 blockers, 0 should-fix, 4 nits. Task 7 marked `[x]`.
  Both review criteria met, discharged empirically (fixtures under `mktemp -d`, `env -i`, fake
  `HOME`, real bundled `templates/default`, repo confirmed unmodified). Success path exits 0
  with a regular, executable `run_harness.sh` at the workspace root digest-identical to the
  template original and *absent* from `.sandbox` (moved, not copied); `.sandbox` retains an
  executable `start.sh`, `.gitignore`, `hooks/`, `profile.template.json`.
  (a) **Post-condition ordering accepted.** The `die 7` `start.sh` sub-case does leave a
  workspace with `run_harness.sh` present and a non-executable `.sandbox/start.sh` — a state
  Task 5 will *not* see on a re-run, so the checklist's "Task 5 detects and repairs" story does
  not cover it. That is not a gap: this state is covered by a *different*, equally documented
  path. Task 2 branch 3 finds the executable `run_harness.sh`, tests `.sandbox/start.sh` and
  exits 3 — precisely the map's "workspace defect the user can fix in place", with the message
  naming the exact `chmod +x`. After that `chmod`, the next run hands over; if `defaults.sh` is
  also absent (Task 8 never ran), the template's `run_harness.sh` L8–11 aborts naming the
  missing file. Every step of the recovery chain fails loud and names its fix, so the user is
  never stranded and never silently degraded. Reordering the `start.sh` check ahead of the `mv`
  would trade one documented terminal state for another and contradict the plan's explicit
  "Then re-assert" wording — not worth the churn. Note that this sub-case is unreachable unless
  `cp -R` misbehaves, since Task 4 already validated both mode bits in place (R2-1).
  (b) **`mv` safety rests entirely on Task 2, as mandated.** No redundant existence check was
  added at this site, and none should be: Task 2's ladder is total — exit 9 (non-regular),
  exit 2 (non-executable), exec/handover (executable) — so L178 is reached only when nothing
  exists at `$workdir/run_harness.sh`. A duplicate guard here would be dead code asserting an
  invariant already proven upstream. Bare-`-f` grep still clean: every hit is a `[[ -f ]]` test
  or the L19 `readlink -f` prose comment; no `-f` appears as a command flag anywhere, so the
  `mv` cannot clobber and Q19 holds.
  (c) **Exit 1 for a failing `mv` is correct.** `mv` is not wrapped in `die`, so a permission
  failure propagates through `set -e` as exit 1 — verified with `chmod 555 "$workdir"`: exit 1
  with `mv: … Permission denied` on stderr, unswallowed. This is exactly the map's "uncaught
  `set -e` failure"; a dedicated code would imply a user-facing contract for a condition with no
  script-side remedy, and `mv`'s own diagnostic already names the path and the cause. No
  `|| true`, no `2>/dev/null`.
  Message style matches Task 4's `die 7` (names the template, states the real cause — mode
  preservation — and deliberately offers no workspace `chmod`). Bash 3.2-safe (`[[ ]]` only).
  Preamble, `# VERSION 2` and the bare `script_dir="$(resolve_script_dir)"` with its Fail-Loud
  comment undisturbed; `exec` count still exactly 1; `bash -n` and `/bin/bash -n` clean; no
  speculative Task 8/10/11 code beyond the marker comment. End-to-end re-invocation takes Task
  2's fast path, `exec`s the real `run_harness.sh`, forwards `--resume` and `arg with space`
  byte-exactly with CWD at the workspace root, and emits none of the provisioning stderr —
  discharging Task 9 nit (3) against both real call sites.
  Nits (non-blocking): (1) checklist L343–345 now understates the partial-failure story — the
  copy/`mv`/post-condition window can also leave a state that re-runs into exit 3, not Task 5;
  worth one clause when the Chronicler archives; (2) the two `die 7` messages differ only in the
  filename, so a future third file invites copy-paste drift — a small loop over
  `run_harness.sh:$workdir` / `start.sh:$workdir/.sandbox` would be Bash 3.2-safe if this block
  is ever touched; (3) `-x "$workdir/.sandbox/start.sh"` is also true for an executable
  directory at that path — same as Task 2 nit (3), unreachable here since `cp -R` reproduces the
  template's regular file; (4) leak set unchanged at seven; this task introduces no new
  top-level scratch names.
- **Task 8 — Round 1: APPROVED.** 0 blockers, 1 should-fix, 3 nits. Task 8 marked `[x]`.
  All four review criteria met, discharged empirically (fixtures under `mktemp -d`, `env -i`,
  fake `HOME`; repo confirmed unmodified, no new untracked files). All five harnesses emit
  exactly the three mandated lines, verified with `cat -A`: no shebang (R2-8 holds), no `^M`,
  no trailing whitespace, `SANDBOX_COMMAND="<harness>"` quoted and matching the selection
  exactly, `SANDBOX_COMMAND_DEFAULTS=()` verbatim. Sourcing is clean under `set -u` on
  `/bin/bash` 3.2.57 *and* bash 5.3.15 (array length 0, no unbound-variable error) — the
  primary-platform criterion is discharged on the real Bash 3.2, not by construction. A
  template-provided `defaults.sh` carrying a custom `SANDBOX_COMMAND` and a populated defaults
  array survives with an identical `shasum` and the preservation is logged (Q8 / checklist
  bullet). Idempotent across runs. The real bundled `templates/default` ships no `defaults.sh`,
  so the generation branch is the one that fires in production.
  (c) **Heredoc correct (S10 / R2-4 closed in code).** Unquoted `<<EOF`, `$harness` the sole
  expansion, no escaping added, `EOF` unindented and column-0 (no `<<-`/tab hazard). No
  injection surface: `$harness` is either an element of `HARNESSES` copied out of the array
  (L79–81, never the raw `NONO_HERE_HARNESS` string) or `select`'s result variable, which can
  only be a list element. A hostile override cannot reach the heredoc — it dies at L86 with
  exit 8. The value is also emitted inside double quotes, so even a hypothetical value with a
  `"` or `$` would corrupt the file rather than execute at generation time; unreachable today.
  (d) **Confirmed: a genuine gap in the plan's task decomposition, not a Builder omission.**
  Provisioning now falls off the end of the script and exits 0 without ever calling
  `handover "$@"`. Q4 and Q15's ordering (`… → defaults → exec`) and Task 9's criterion
  ("provisioning path and fast path are indistinguishable") all require it, yet **no task owns
  the wiring**: Task 8's description ends at `defaults.sh`, and Task 9 was approved as
  definition-only precisely because inventing a call site then would have been speculative.
  The call belongs at the **end of Task 8's block** (after the `if/else`, at top level, so it is
  reached on both the preserved and the generated branch) but should be **scheduled as its own
  task** — it is the last statement of provisioning and its acceptance test is Task 9's
  argv-recording stub run against *both* call sites, which is Task 9's criterion, not Task 8's.
  Recommendation: add **Task 8b — "Wire the provisioning handover"**: append `handover "$@"` as
  the final statement, and re-verify `exec` count is still exactly 1 (it will be — `handover` is
  a call, not a second `exec`). Do not fold it into Task 10 or 11; it is production control flow.
  Until it lands, provisioning leaves the user at a shell prompt with a correct sandbox and no
  running harness — a visible, non-silent shortfall, so no Fail-Loud violation, but the feature
  is incomplete.
  Fail Loud upheld: no `|| true`, no `2>/dev/null`, no `-f` in this block. The `cat >` redirect
  is unguarded, so a write failure propagates through `set -e` — verified with `chmod 555
  .sandbox`: exit 1 with `Permission denied` on stderr, unswallowed. Bash 3.2-safe (`[[ -e ]]`,
  `cat`, heredoc; no `${arr[@]+…}`, no `printf -v`). `bash -n` and `/bin/bash -n` clean;
  preamble, `# VERSION 2` and the bare `script_dir="$(resolve_script_dir)"` with its Fail-Loud
  comment undisturbed; no speculative Task 10/11 code.
  - **T8-S1 SHOULD — the preservation log is the only stderr line in the script without the
    `$SELF:` prefix.** It reads `'…/.sandbox/defaults.sh' already exists; preserved untouched.`
    while `workdir:` (L126) and `template:` (L127) — the two closest precedents, both non-abort
    provisioning logs, not aborts — both carry it, as does every `die`. The plan's "every abort
    writes a `$SELF`-prefixed message" rule is about aborts and does not literally reach a log
    line, but the script's own established convention does, and the point of the prefix is that
    stderr interleaved with the harness's own output stays attributable to `nono-here.sh`.
    Consistent with the accuracy/consistency standard applied to Task 1's export comment.
    Fix: `echo "$SELF: '$workdir/.sandbox/defaults.sh' already exists; preserved untouched." >&2`.
    Non-blocking — cosmetic on stderr, zero behavioural effect — but land it before Task 11
    case (12) pins the current text into an assertion.
  Nits (non-blocking): (1) `[[ -e ]]` is false for a **dangling symlink** `defaults.sh` (BSD
  `cp -R` copies symlinks as links, so a template *can* ship one), sending it to the `else`
  branch where `cat >` follows the link and writes the generated content to the link's target —
  outside `.sandbox` if the link points there. Not a security boundary (a template already ships
  the `run_harness.sh` we execute) and not silent (if the target's parent is missing, `cat`
  fails loudly through `set -e`), so it does not rise to the Task 2/Task 6 `|| -L` treatment;
  Task 4 validates only `run_harness.sh` and `start.sh`, so no upstream guard exists either.
  Noted, not required. (2) The converse: a **directory** named `defaults.sh` satisfies `-e` and
  is "preserved" — a genuinely wrong success, but it fails loudly one step later when
  `run_harness.sh` sources it. Both cases would be closed by a single
  `[[ -f "$workdir/.sandbox/defaults.sh" ]]` plus an `-e || -L`/`! -f` ⇒ `die 9` guard mirroring
  Task 2, if this block is ever touched. (3) Leak set unchanged at seven; this task introduces
  no new top-level scratch names.
- **Task 8b — Round 1: APPROVED.** 0 blockers, 0 should-fix, 3 nits. Task 8b marked `[x]`.
  All five review criteria met, discharged empirically (fixtures under `mktemp -d`, `env -i`,
  fake `HOME`; repo confirmed unmodified). Scope reviewed: `nono/nono-here.sh` L203–207 only;
  `templates/default/run_harness.sh` is Task 10 and was excluded.
  (a) **Placement correct.** `handover "$@"` (L207) sits at column 0, after the Task 8
  preserve/generate `if/else` closes at L201 — top level, not nested in either branch, so both
  branches reach it unconditionally. Verified empirically on both: generate branch reaches the
  stub; preserve branch reaches the stub *and* leaves the shipped `defaults.sh` byte-identical
  (`shasum` 2717912f… before and after) with the preservation log emitted. Placement after the
  `if/else` rather than duplicated inside each branch is the correct choice — DRY, and it makes
  the call structurally unconditional rather than conditional-by-coincidence, which is what the
  headline regression was.
  (b) **B5 invariant holds.** `exec` count is exactly 1 (L59, inside `handover()`); L54/205/206
  are comments. Task 8b adds a *call*, not a second exec, exactly as the task mandated. The
  single-exec-site invariant tracked since B5 is intact for the third consecutive task.
  (c) **Control-flow totality confirmed — no implicit exit-0 path survives.** Walked end to end:
  L43 `script_dir` (bare assignment, `set -e`-aborting) → L49 `workdir` (always yields a value)
  → L62–71 Task 2 ladder: non-regular ⇒ die 9, non-`+x` ⇒ die 2, valid ⇒ die 3 or `handover`
  (execs, never returns), absent ⇒ the sole fall-through → L77–101 selection: die 8 / die 4 /
  die 10, else `$harness` non-empty → L106–124 template probe: die 5, else `$template` set →
  L129–136 die 7 → L142–159 die 6 or `rm -r` → L171–173 die 9 → L175–189 `mkdir`/`cp`/`mv`
  unguarded (propagate via `set -e` as exit 1, per the map) plus die 7 ×2 → L193–201 both
  branches → **L207 `handover "$@"`, the script's last statement, which execs or dies.**
  `handover()` cannot return: it either `exec`s or `die`s on a failing `cd` (exit 1, mapped).
  There is no remaining path that falls off the end and exits 0 implicitly. The only non-`die`
  terminations are `set -e` propagations from `mkdir`/`cp`/`mv`/`cat`, each of which surfaces
  the failing command's own stderr — loud, not silent.
  (d) **The bundled-template exit 127 is correct, disclosed behaviour, not a Fail-Loud
  violation.** It proves the handover *occurred*: control reached the copied `run_harness.sh`,
  which reached `.sandbox/start.sh`, which failed because the external `nono` binary is absent
  on the test machine. Requirements L16–17 assign that check to `.sandbox/start.sh`, explicitly
  **not** to `nono-here.sh`. A loud non-zero exit from the correct owner is precisely the
  mandated behaviour; silently substituting or skipping the harness would be the violation.
  Out of Task 8b's scope either way.
  Argv fidelity discharged: `--resume` and `arg with space` arrive as exact separate arguments
  (`cat -A`), and `$PWD` is the workspace root even when invoked from `nested/deeper` — the
  `cd` in `handover()` doing its job. **Task 9's long-deferred criterion is now finally
  satisfied against two real call sites:** provisioning run and fast-path run with identical
  argv produced byte-identical records (SHA-1 77792f37…). Fast path unchanged — run 2's stderr
  was 0 bytes, no `workdir:`/`template:` lines (N13 holds). Cold workspace provisioned **and**
  handed over in a single invocation: exit 0, stub invoked on the first run, `run_harness.sh`
  at the workspace root, `.sandbox/` populated, `defaults.sh` generated. Q4 and Q15's
  `… → defaults → exec` ordering are now both satisfied in code.
  `bash -n` and `/bin/bash -n` clean; Bash 3.2-safe (a bare function call and `"$@"`; no new
  constructs). Preamble, `# VERSION 2` and the bare `script_dir="$(resolve_script_dir)"` with
  its Fail-Loud comment undisturbed. No speculative code — four lines, three of them the
  comment that records *why* no second `exec` was added. Fail Loud, Never Fake respected: no
  `|| true`, no `2>/dev/null`, no `-f` flag introduced.
  Incidentally verified: **T8-S1 is closed** — the preservation log (L194) now carries the
  `$SELF:` prefix, matching every other stderr line in the script.
  Nits (non-blocking, no rework): (1) L206 credits `handover()` to "Task 9", which is accurate
  but will read oddly once the plan is archived and task numbers lose context — the Chronicler
  may prefer "the single exec site"; (2) Task 9's nit (2) is now load-bearing at a *second*
  site: if `exec` fails here the script dies 126/127 with no `$SELF` message. Acceptable only
  because L184's post-condition `-x` check immediately precedes it — that guard must not be
  dropped, same standing order as Task 2's; (3) leak set unchanged at seven — this task
  introduces no new top-level scratch names.
- **Task 10 — Round 1: APPROVED.** 0 blockers, 0 should-fix, 5 nits. Task 10 marked `[x]`.
  Scope reviewed: `nono/templates/default/run_harness.sh` (28 lines, working tree) only.
  Task 11 absence not flagged; `nono-here.sh` out of scope. **Disclosed limitation:** no shell
  tool was available to me this round, so the Builder's execution evidence (both bash 3.2.57 and
  5.3.15) is accepted as reported and cross-checked against the file by reading; every claim
  below that is *not* execution-dependent was verified in the source directly.
  All four review criteria met.
  (a) **Defect (a) closed at the root.** The normalisation line is *deleted*, not re-assigned —
  a repo-wide grep for `SANDBOX_COMMAND_DEFAULTS` yields exactly two sites: the generator in
  `nono-here.sh` L199 and the single use site at `run_harness.sh` L21. There is no assignment
  anywhere in `run_harness.sh`, so defect (b) cannot be reintroduced through the back door.
  The `${arr[@]+"${arr[@]}"}` idiom is correct on Bash 3.2 and expands to nothing for *both*
  empty and unset arrays there (an empty array is treated as unset by the `+` test — which is
  exactly why the inner `"${arr[@]}"` is never evaluated and `set -u` never fires). The
  asymmetric quoting is deliberate and correct: the outer expansion must stay unquoted so that
  it can vanish entirely rather than yielding one empty word, while the *inner* expansion is
  quoted and, per the `${parameter+word}` semantics, those quotes are honoured during word
  expansion. **A default containing a space is therefore not split, and globs in a default are
  not expanded.** Plainly stated as the criterion demands: this idiom is safe for
  space-bearing defaults. Evidence gap noted as nit (1) — scenario (vi) exercised a
  space-bearing *argument*, not a space-bearing *default*.
  (b) **`||` order intact** at L20: `[[ $# -eq 0 || "${1:-}" == -* ]]`, with `$# -eq 0` still
  first, so `$1` is dereferenced only when at least one argument exists. The `${1:-}` at that
  site is consequently **redundant but harmless** belt-and-braces; the `${1:-}` at L24 is the
  one that is genuinely load-bearing — that is B2's exact case (empty/unset defaults, no args,
  `$#` still 0 after L21), and without it the script is unbound under `set -u` on every shell.
  Keeping both is the right call: it makes the guard invariant rather than dependent on
  short-circuit order surviving a future edit.
  (c) **`"$WORKSPACE/.sandbox/start.sh"` correct.** `WORKSPACE` is assigned unconditionally at
  L5 via `git rev-parse --show-toplevel 2>/dev/null || echo "$PWD"`, which always yields a
  value, so `set -u` cannot fire and no `${WORKSPACE:-}` guard is needed. The whole path is
  inside one pair of double quotes, so a workspace path containing spaces is a single word;
  it is also absolute in both branches, so no `PATH`/`CDPATH` interaction exists. This removes
  the script's silent dependency on the caller's CWD — the previously live failure mode the
  Builder reproduced (exit 1, `.sandbox/start.sh: No such file or directory`) rather than
  merely reasoned about. Note the `2>/dev/null` at L5 is the pre-existing, plan-sanctioned
  not-a-repo probe with an explicit disclosed fallback — unchanged by this task and not a
  Fail-Loud violation.
  (d) **Task 8 interaction confirmed.** `nono-here.sh` L196–200 generates exactly
  `SANDBOX_COMMAND="$harness"` / `SANDBOX_COMMAND_DEFAULTS=()`, so **the empty-array case is
  the default state of every freshly provisioned workspace** — scenario (i) is the common path,
  not an edge case, and this task is a correctness prerequisite for Task 8b's handover rather
  than a hardening nicety. The generated file sources cleanly here: L13 `source` under
  `set -u`, then L14's `${SANDBOX_COMMAND:-}` guard and the L15 emptiness check with exit 2.
  (e) **The `# VERSION 3` bump is inert and triggers no warning path — and the premise that
  `start.sh` reads it is false.** `start.sh` compares *only* `profile.json`'s `.meta.version`
  against `profile.template.json` via `jq` (L28–39); it never opens `run_harness.sh` and
  contains no `# VERSION` marker itself. A repo-wide grep finds the `# VERSION` token at
  exactly two sites — `nono-here.sh` L3 (`2`) and `run_harness.sh` L2 (`3`) — and **no reader
  anywhere**. So no "your config is older than the template" path can fire, and the two numbers
  being out of step is not a defect. Recorded as nit (2): the marker is provenance-only today.
  Fail Loud, Never Fake respected — no `|| true`, no `2>/dev/null` and no `-f` flag introduced;
  the missing-defaults (exit 1) and empty-`SANDBOX_COMMAND` (exit 2) aborts both name the
  offending file and are untouched. Bash 3.2-safe throughout (`[[ ]]`, `set --`,
  `${arr[@]+…}`, `${1:-}`; no `mapfile`, no `local -n`, no `${arr[@]:-}`). `#!/usr/bin/env bash`,
  `set -euo pipefail`, 4-space continuation indent and the file's existing style all preserved.
  No speculative code: the diff is one deletion, two `${1:-}` guards, one use-site rewrite, one
  path qualification and the version bump — nothing anticipating Task 11.
  Nits (non-blocking, no rework): (1) **evidence gap, not a defect** — no scenario exercised a
  *default* containing a space (e.g. `SANDBOX_COMMAND_DEFAULTS=("--msg" "hello world")`); the
  idiom is sound by construction, but Task 11 case (13) should pin it, since that is the only
  property distinguishing this idiom from the naive rewrite. (2) `# VERSION` in both scripts is
  written by hand and read by nothing; either wire it to something or let the Chronicler record
  that it is documentation-only, before someone assumes a drift-detection mechanism exists.
  (3) L21 prepends defaults *before* the L24 `SANDBOX_COMMAND` shift, so a defaults array whose
  first element happens to equal `$SANDBOX_COMMAND` would have that element silently shifted
  away and then re-added by L28 — net behaviour identical, so harmless today, but the two blocks
  are order-coupled in a way no comment records. (4) If a hand-written `defaults.sh` sets
  `SANDBOX_COMMAND_DEFAULTS` as a plain *string* rather than an array, L21 expands it as a
  single word rather than failing — benign, and out of scope. (5) L15 uses `[[ "$X" = "" ]]`
  where the rest of the file uses `==`; cosmetic, pre-existing, untouched by this task.
- **Round 3:** N/A
