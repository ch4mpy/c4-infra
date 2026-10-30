# Plan: A run waiting for the suite's lock can be overtaken by later runs, without bound

- Spec: [v1](spec.md) (approved 2026-10-29: PA-01 A, PA-02 A)
- Status: approved
- Branch: 0037-suite-lock-has-no-queue
- Approved: 2026-10-29, Jérôme Wacongne (engineer, also PO and tech lead; in the session, its three open choices decided as recommended)

## Starting point

Read on 2026-10-29, the branch at 0628a78 (the intent, spec v1 approved, on top of `main` 8f0a090).

- **The lock** (`tests/lib/suite-lock.sh:8-41`): a container named `$SUITE_LOCK_NAME`, `alpine:3`, fed by a pipe from the run through a process substitution (`:14`), `held` once it runs (`:21`), `is already in use` while another run holds it (`:26`); a retry every 2 s (`:39`); the holder line printed on a change (`:36`). `tests/run.sh:374` calls it; `:17` says "a run waits for another's end". Tests and lanes get `{SUITE_LOCK_FD}>&-` (`tests/run.sh:191`, `:213`).
- **Its tests**: `tests/0017-run.sh` (AC-06: a second run waits and names the holder, `waited_for` anchored at the line's end, `:245-246`; kill -9, Ctrl-C and a failed run don't hold the next one, `starts_within 10`; runs started "as a terminal" with `perl … setpgrp`, `:236-238`) and `tests/0022-lanes.sh`, both with a lock of their own (`SUITE_LOCK_NAME=c4-infra.suite-lock-00NN-$$`), both `# covers: tests/run.sh tests/lib/suite-lock.sh`. A change of `tests/lib/` runs every test (CLAUDE.md).
- **0017's facts** (`tests/0017-run.sh:10-13`, Linux with Docker Desktop): the pipe-fed container goes within a second when its run exits, fails, gets SIGINT or `kill -9`. Under Git Bash the suite's runs pass 0017's AC-06 (the lock freed after `kill -9`), but nothing measured a ticket-like container there.
- **The skills** take the same lock through their copy (`~/.claude/tests/run.sh:166-171`, slow tier only), same code (`diff`, 2026-10-29). Their intent home is in bootstrap too; their next number is 0119 (`origin/0118-…` the last).
- **Docs**: CLAUDE.md "Verification" (`:22`) describes the wait; no other doc names the lock's behaviour (the intent home aside).
- **Linux**: the stand-in host (`tests/lib/stand-in-host.sh`) is Ubuntu 24.04 with Docker, `perl` (`setpgrp` checked in `ubuntu:24.04`, 2026-10-29) and `tar` (used by `0013-upgrade.stand-in.sh`); `stand_in_load_image` copies an image from the workstation (`:98-104`), so no Docker Hub pull (0020).

## Decisions (Jérôme Wacongne, engineer, 2026-10-29, in the session)

- AC-07's Linux proof is a permanent stand-in test (`tests/0037-queue-linux.stand-in.sh`, in `--all`).
- Every run takes a ticket, an unhindered one included.
- Tonight's work stops before `/sdlc-ship`: implemented, verified and pushed on the branch; nothing on `main`.

## Design (how the spec's protocol is built)

- `suite_lock_take` first starts a **ticket**: a container fed by a pipe from the run, as the lock is (`alpine:3`, `sh -c 'echo queued; exec cat > /dev/null'`), named `$SUITE_LOCK_NAME.queue.<pid>-<random>`, labels `c4-infra.suite.queue=$SUITE_LOCK_NAME`, `c4-infra.suite.worktree=$PWD`, `c4-infra.suite.started=<start>`. Every run takes one, a run with no one ahead included (one path, no window where a newcomer passes a run about to take the lock; about a second more for an unhindered run, measured at step 0).
- Each second: the queue is the **running** containers labelled with this lock's name (a ticket created but never started doesn't count), ordered by `.State.StartedAt` from the daemon (its fraction padded to 9 digits: Docker trims trailing zeros), ties by `.Id`. The run's place is its ticket's rank. At place 1 it tries the lock as today; holding it, it closes its ticket's pipe and returns. Otherwise it prints the holder line on a change (inspected from the lock's container, so a holder of the skills' copy is named too) and `place in the queue: <n>` on a change.
- The wait loop's own children (`sleep`, `docker`) get `{fd}>&-` for the ticket's pipe, so a killed run's ticket goes as soon as its `docker run` sees the end of its input.
- A ticket gone while its run waits (removed by hand) → the run takes a new one, at the back; the place line shows it.
- Factored once: starting a pipe-fed container and waiting for its word, used for the lock and the ticket.
- The header states the protocol (RQ-06): the ticket's name and labels, the order (`StartedAt`, then `Id`, running only), "try the lock only at place 1, drop the ticket once held", the 1 s period, how to clear a queue by hand.

## Files

| File | Change | For |
| --- | --- | --- |
| `tests/0037-queue.sh` | new: the library sourced by background runs in their own directories (their "worktrees"), a lock of its own (`c4-infra.suite-lock-0037-$$`), each run logging its start and end; scenarios: A holds, B, C, D queued in turn (each started once the previous one shows its place) → AC-01, AC-02; B killed with `kill -9`, then interrupted (Ctrl-C to its process group) behind A with C queued → AC-03; an unhindered run, two locks' queues apart → AC-04; a run of the unqueued library between queued runs → AC-05; header and CLAUDE.md lines → AC-06. Cleanup kills every run and removes the lock's and tickets' containers. `# covers: tests/lib/suite-lock.sh tests/fixtures/0037/` | RQ-01 to RQ-06, RQ-08; AC-01 to AC-06 |
| `tests/fixtures/0037/suite-lock-unqueued.sh` | new: `tests/lib/suite-lock.sh` as `main` has it (8f0a090), the skills' copy's behaviour, for AC-05 | RQ-05, AC-05 |
| `tests/lib/suite-lock.sh` | modified: the ticket, the queue's order, the place line, the header's protocol | RQ-01 to RQ-06 |
| `CLAUDE.md` | modified: "Verification" (`:22`): waiting runs take the lock in the order they arrived and print `place in the queue: <n>` | RQ-08, AC-06 |
| `tests/run.sh` | modified: header line `:17` only (waiting runs queue in arrival order) | RQ-08 |
| `tests/0037-queue-linux.stand-in.sh` | new: on a stand-in (Ubuntu, bash, its own Docker), `alpine:3` loaded, the library, `assert.sh`, `tests/0037-queue.sh`, its fixture and CLAUDE.md copied in with `tar`, the test run there: `every check passed`. `# covers: tests/lib/suite-lock.sh tests/0037-queue.sh tests/fixtures/0037/` | RQ-07, AC-07 |
| `docs/intent/0037-…/plan.md`, `intent.md`, `docs/intent/README.md` | this plan, *Deviations*, `## Verification`; status `planned`, then `delivered`; the index row | — |

Unchanged on purpose: the lock's container, name and labels (RQ-05); `tests/0017-run.sh`, `tests/0022-lanes.sh` (AC-04: they pass unchanged); the skills' repository (PA-01 A: its twin intent is drafted apart from this plan).

## Order of work

**Bootstrap mode** (the intent's `Mode`): no PR, one `sdlc-verify` round, pushes without confirmation, on the intent's branch (0035 and 0036 in progress). A bug: the failing test first, committed alone, then frozen (`.claude/frozen-tests.local`).

0. **Setup and facts.** — skill: none — check: `git status --short` empty; each fact's command and lines under *Deviations*.
   - `git merge origin/main` if `main` moved.
   - (a) `.State.StartedAt` of two `alpine:3` containers started in turn, on Docker Desktop and in the stand-in's Docker: RFC 3339 in UTC (`Z`), trailing zeros trimmed; the padded form sorts them in start order.
   - (b) Under Git Bash: a pipe-fed `alpine:3` container (the ticket's form) after `kill -9` of the bash that feeds it, a `sleep 1` child holding the pipe or not: gone within how many seconds.
   - (c) A container created and not yet running is absent from `docker ps --filter label=…`; `--filter label=k=v` matches the value exactly (not `c4-infra.suite-lock-0037-1` for `c4-infra.suite-lock`).
   - (d) One loop's cost on Docker Desktop (`docker ps` + `docker container inspect` of three tickets) and a ticket's start: under a second each, else the period goes to 2 s for a place above 1 (a deviation).
1. **Failing test.** — skill: none — check: `TMPDIR=~/.cache/c4-infra-tests bash tests/0037-queue.sh` exits 1, its KO lines the place lines (AC-02, AC-03's within 5 s) and AC-06's; AC-04 and AC-05 `ok` (the exclusion holds today); AC-01 either way (the order holds by chance with three runs, so AC-02 is the deterministic proof). The KO lines under *Deviations*.
   - Commit `test(0037): runs waiting for the suite's lock queue in arrival order and say their place`, then freeze `tests/0037-queue.sh` and the fixture.
2. **The library.** — skill: none — check: `bash -n tests/lib/suite-lock.sh`; `TMPDIR=… bash tests/0037-queue.sh`: every check but AC-06's CLAUDE.md line `ok`; `bash tests/0017-run.sh` and `bash tests/0022-lanes.sh` pass.
   - Commit `fix(0037): waiting runs take the suite's lock in arrival order and print their place`.
3. **The docs.** — skill: none — check: `TMPDIR=… bash tests/0037-queue.sh` ends `every check passed`.
   - CLAUDE.md `:22`, `tests/run.sh:17`. Commit `fix(0037): CLAUDE.md says waiting runs queue and print their place`.
4. **Linux.** — skill: none — check: `TMPDIR=… bash tests/0037-queue-linux.stand-in.sh` ends `every check passed`.
   - Commit `test(0037): the queue on a Linux Docker, in the stand-in`.
5. **Verification.** — skill: sdlc-verify — check: `verification passed`.
   - `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --changed --all`: every test (`tests/lib/` changed), one stand-in lane, its own lock taken through the new queue.
   - Mutation checks in a throwaway worktree, each on `tests/0037-queue.sh`: M1 the order by `.Created` name instead of `StartedAt` → still ok or KO recorded (informative); M2 the place-1 condition removed (every run tries the lock) → AC-01 or AC-02 KO; M3 the ticket's pipe left open in the wait loop's children → AC-03 within 5 s KO if fact (b) says so. Lines under *Deviations*.
   - `/sdlc-verify 0037`: bootstrap, standard risk: one round, the bugs pass. Evidence into `## Verification`, commit `plan: verification of 0037`; unfreeze; push.
6. **Delivery.** — skill: sdlc-ship — `/sdlc-ship 0037`, by the PO. The push of `main` runs the demo workflow (tests and CLAUDE.md are not `**/*.md` only): the same files redeployed.

## Risks

- Docker's `StartedAt` text doesn't sort as time (trimmed zeros) → padded to 9 digits, fact (a) on both Dockers.
- A ticket created but never started (its run killed between create and start) blocks the queue → only running tickets count (fact c); `--rm` removes it if it ever starts.
- A killed waiting run's ticket lingers past 5 s under Git Bash (MSYS keeps the pipe) → children get `{fd}>&-`; fact (b) measures it before the design is coded; AC-03 checks it on both systems.
- A waiting run of the skills' copy takes the lock between queued runs → accepted (PA-01 A); AC-05 proves the exclusion still holds.
- The frozen test is wrong somewhere → a deviation, stopped and recorded; the night's decisions are flagged for the PO's validation.
- Many waiting runs poll Docker each second → fact (d); a place above 1 can poll every 2 s.
- The test's own runs collide with the suite's lock → its own `SUITE_LOCK_NAME`, its tickets keyed by it (AC-04's two queues).

## Proof

| Criterion | How | Test, command or check |
| --- | --- | --- |
| AC-01 | automated test | `tests/0037-queue.sh`, "AC-01: B, C and D run in arrival order, none before the previous one's end" |
| AC-02 | automated test | `tests/0037-queue.sh`, "AC-02: …place 1 / 2 / 3, each after the holder's line" and "…then C 1, D 2"; KO at step 1 |
| AC-03 | automated test | `tests/0037-queue.sh`, "AC-03, kill-9 / interrupted: C is first within 5 s" and "…starts once A ends"; KO at step 1 |
| AC-04 | automated test | `tests/0037-queue.sh`, "AC-04: an unhindered run holds the lock within 10 s, printing nothing" and "two locks' queues apart"; `tests/0017-run.sh` and `tests/0022-lanes.sh` pass unchanged |
| AC-05 | automated test | `tests/0037-queue.sh`, "AC-05: a run of the unqueued library never holds the lock beside a queued run" |
| AC-06 | automated test | `tests/0037-queue.sh`, "AC-06: the header states the protocol" and "CLAUDE.md names the order and the place line" |
| AC-07 | automated test | Git Bash: `tests/0037-queue.sh` on the workstation; Linux: `tests/0037-queue-linux.stand-in.sh` |
| No regression | command | `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --changed --all`, `verification passed` |

## Deviations

- 2026-10-29 — step 0, the facts, on Docker Desktop 29.9.2 under Git Bash: (a) `.State.StartedAt` of two `alpine:3` started in turn: `2026-10-30T08:23:24.853841622Z`, `2026-10-30T08:23:25.205878224Z` (RFC 3339, UTC `Z`, nanoseconds; the stand-in's Docker is measured at step 4 by the Linux test itself); (c) a created, never started, container labelled for the queue is absent from `docker ps --filter label=c4-infra.suite.queue=<lock>`, and a container labelled `<lock>-other` too: the filter matches the value exactly; (d) `docker ps` + `docker container inspect` of the queue: 0.24 s, `docker run -d` of a ticket: 0.36 s, so the 1 s period holds; (b) a pipe-fed `alpine:3` container after `kill -9` of the bash feeding it: gone after 1.0 s with a `sleep 1` child keeping the pipe, 0.6 s with the child's copy closed (`{fd}>&-`).
- 2026-10-29 — step 1: the library was drafted in the working tree before the test's commit, to run the test against it once (its harness, not the fix, was being checked: two test fixes came of it, the wait for X and Z's end, and the wait for a free lock before AC-04's lone run, whose `docker run` could otherwise meet the previous holder's container still going). The test was then committed alone, at e50ef2b, and frozen. The test's check names differ from the *Proof* table's wording (e.g. "AC-02: B is 1st", "AC-03, kill-9: W-kill-9 is 1st within 5 s"): same criteria.
- 2026-10-29 — step 1, `TMPDIR=~/.cache/c4-infra-tests bash tests/0037-queue.sh` with the library as `main` has it (the working tree's copy reset to HEAD's): exit 1, `27 check(s) failed` after 190 s. KO: every place line (`AC-02: B/C/D waits and prints its place`, `… names A's run, then its place`, `B is 1st`, `C is 2nd`, `D is 3rd`, `then C is 1st`, `and D 2nd`, `then D is 1st`), `AC-01: B runs once A ends` and `AC-01: B, C and D ran in arrival order, each after the previous one's end` (another run took the lock before B: the bug), `AC-03, kill-9 / interrupted: K waits 1st`, `W waits 2nd`, `W is 1st within 5 s`, `AC-04: each queue counts its own runs: Y is 1st on H's lock`, `Z is 1st on X's`, and the five AC-06 lines. `ok`: AC-03's runs once the holder ends and the killed run never ran, AC-04's lone run (within 10 s, printing nothing) and the other lock's, both `apart` checks, the four AC-05 checks: the exclusion holds today.
- 2026-10-29 — steps 2 to 4: `tests/0037-queue.sh` with the library, then with CLAUDE.md: `every check passed` (49 `ok`); `tests/0017-run.sh` (45 `ok`) and `tests/0022-lanes.sh` (50 `ok`): `every check passed`; `tests/0037-queue-linux.stand-in.sh`: the 49 checks pass on the stand-in's Linux Docker, which orders the queue by its own clock (fact (a) on Linux, by the test).
- 2026-10-29 — step 5, the review round (`code-review`, high), fixed in the library: a `docker ps` that fails for a moment no longer reads as a ticket gone (the run keeps its ticket and tries again; only "No such container" sends it to the end); the holder removes its ticket once it holds the lock, so a newcomer never counts it; the loop's `docker` calls and the lock attempt's waits close the ticket's pipe too (the plan's design said so, only `sleep 1` did); the queue lists tickets by name, ties broken by name (one `docker container inspect` less, the header says so); a failed start names its container. The Linux test's `# covers:` adds CLAUDE.md (AC-06 reads it). Answered, not changed: a run stopped at place 1 (Ctrl-Z) holds the queue up, as a stopped holder holds the lock today; the header says how to send it to the end (`docker rm -f <its ticket>`); `tests/0037-queue.sh`'s own `# covers:` lacks CLAUDE.md, but the test is frozen: for the PO, after delivery; three to four docker calls a second per waiting run (fact (d): 0.24 s a loop), accepted; the perl launcher of a terminal, now in three tests (0017, 0022, 0037): a shared helper is another change. Then `tests/0037-queue.sh`: `every check passed`.
- 2026-10-30 — step 5, the verification command at 9e6a7ce, every test (`tests/lib/` changed), one stand-in lane (Docker reports 7.6 GiB): `total: 4196.6 s for 81 test(s)`, FAILED 0016-keycloak-facts, 0017-export-realm, 0019-collation, 0029-description, 0029-image-facts, 0030-federation-ids. **0019-collation is this change's**: a bare `sort -n` at `tests/0037-queue.sh:122`, in the frozen test (the test exports `LC_ALL=C`, so the order is already the C one, but the suite's convention refuses it). Not fixed: an edit of the frozen test is the PO's decision, proposed with the other one already pending, `LC_ALL=C sort -n` there and CLAUDE.md in its `# covers:`. The five others fail the same way at `origin/main` 8f0a090, in a throwaway worktree: 0029-description (a), intent 0038; the four Keycloak tests, where a native `jq.exe` (WinGet `jqlang.jq` 1.8.2), and by the verifier's reading curl too, gets an unconverted `/c/Users/…` path under the tests' `export MSYS_NO_PATHCONV=1` (`MSYS_NO_PATHCONV=1 jq .a /c/Users/…/jqprobe.json`: `Could not open file`, from either drive). At main: 0029-image-facts the same 6 KO, 0030-federation-ids the same 16, 0016-keycloak-facts the same 11; 0017-export-realm the same three jq KO, after three more of its own (that worktree had no `.env`). Why these four passed on this workstation before is not established. A bug intent is suggested.
- 2026-10-30 — step 5, mutation checks of `tests/0037-queue.sh` in a throwaway worktree at 9e6a7ce: M1 (`{{.Created}}` for `{{.State.StartedAt}}`): `every check passed`, informative (the two orders agree); M2 (`if :; then` for the place-1 condition): `6 check(s) failed` (AC-01 "B runs once A ends", "C runs once B ends", "B, C and D ran in arrival order"; AC-02 "then C is 1st", "and D 2nd", "then D is 1st"); M3 (every ` {ticket_fd}>&-` of the library dropped, the `exec` that closes the ticket's pipe included, and the lock attempt's waits given no fd to close): `every check passed`, as fact (b) predicts (1.0 s against 0.6 s, both under AC-03's 5 s): the closes are a margin, which no test proves.
- 2026-10-30 — step 5, the verifier: 7 of the 8 rows OK, the no-regression row KO (0019-collation). It reran `tests/0037-queue.sh` at ee0303e (the library and CLAUDE.md as `main` has them): `27 check(s) failed`, the step 1 failures. Two weak proofs, both in the frozen test, for the PO: AC-06's test doesn't check that the header says when a run tries the lock (the header does, `tests/lib/suite-lock.sh:15`); AC-05's case where a run of the unqueued copy takes the lock ahead of the queue is reached by chance only (the exclusion is checked in whatever order occurs).
- 2026-10-30 — after the verification, the product owner (Jérôme Wacongne, in the session) allowed three edits of the test frozen at e50ef2b, which the verification left to them: `LC_ALL=C sort -n` at `tests/0037-queue.sh:122` (0019-collation's KO), CLAUDE.md in its `# covers:` (it reads it), and AC-06's header check also names "the run at place 1 tries the lock" (the verifier's gap; the phrase is in this branch's header, not in `main`'s). No assertion removed or loosened. AC-05's weak proof stays as it is. Then `bash tests/0019-collation.sh`: `every check passed`; `TMPDIR=~/.cache/c4-infra-tests bash tests/0037-queue.sh`: exit 0, 50 `ok`, `every check passed`.

## Verification

### Verification — 9e6a7ce

- **KO, first**: `tests/0019-collation.sh` refuses this change's frozen test, `tests/0037-queue.sh:122` (a bare `sort -n`). Not fixed in this run: the edit of a frozen test is the product owner's decision (proposed: `LC_ALL=C sort -n`, with CLAUDE.md added to its `# covers:`).
- Verification command: `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --changed --all` → `total: 4196.6 s for 81 test(s)`, then `FAILED: tests/0016-keycloak-facts.sh tests/0017-export-realm.sh tests/0019-collation.sh tests/0029-description.sh tests/0029-image-facts.sh tests/0030-federation-ids.sh` (2026-10-30, log `~/.cache/c4-infra-tests/0037-full.log`). 0019-collation is this change's; the five others fail the same way at `origin/main` (Deviations).
- Risk tier: standard (the suite's own tooling: no secret, host, image or deployment changed)
- Reviews: bootstrap mode: 1 round; bugs (`code-review`, high) 6 fixed / 4 answered (Deviations, step 5); no security pass (standard risk); the comments the diff adds are function headers and one suppression's reason.
  - A run stopped at place 1 (Ctrl-Z) holds the queue up: as a stopped holder holds the lock today; the header says how to clear it (`tests/lib/suite-lock.sh:22-24`).
  - Three to four docker calls a second per waiting run: accepted, 0.24 s a loop (fact (d)).
- Mutation check (bug): `tests/0037-queue.sh` fails at ee0303e: `27 check(s) failed` (the session at step 1, then the verifier). M1 `every check passed` (informative), M2 `6 check(s) failed`, M3 `every check passed` (fact (b): no test proves the pipe's closes).
- Verifier: 7/8 rows OK, the no-regression row KO; table below.
- Not verifiable here: none.
- Files outside the plan: none.
- Pre-existing findings (not fixed, out of scope): `tests/0029-description.sh` (a) under Git Bash → intent 0038 (proposed); the four Keycloak tests on the Windows workstation, a native jq or curl given `/c/…` paths under `MSYS_NO_PATHCONV=1` → a bug intent suggested; `tests/0029-image-facts.sh:112-116` passes on nothing when jq fails; `tests/0017-run.sh` ends with `rm: cannot remove '…/other': Device or resource busy` after `every check passed`, at `main` too.
- For the product owner: the frozen test's two edits above, and its two weak proofs (AC-06's "when a run tries the lock", AC-05's overtaking reached by chance).

| Criterion | Result | Evidence |
| --- | --- | --- |
| AC-01 | OK | `TMPDIR=~/.cache/c4-infra-tests bash tests/0037-queue.sh` (verifier, 9e6a7ce): exit 0, 49 `ok`, `every check passed`; "AC-01: B, C and D ran in arrival order, each after the previous one's end" (start and end stamps compared) |
| AC-02 | OK | the same run: "B is 1st", "C is 2nd", "D is 3rd", "then C is 1st", "and D 2nd", "then D is 1st", "names A's run, then its place" (exact sequences of places) |
| AC-03 | OK | the same run: "W-kill-9 is 1st within 5 s", "W-interrupted is 1st within 5 s", "runs once H ends", "ran after H, K never" |
| AC-04 | OK | the same run: "a run alone holds the lock within 10 s", "printing nothing", "Y is 1st on H's lock", "Z is 1st on X's"; `tests/0017-run.sh` 45 `ok` and `tests/0022-lanes.sh` 50 `ok`, unchanged, `every check passed` |
| AC-05 | OK, weak proof | the same run: "AC-05: both ran, never at the same time as another"; the unqueued copy taking the lock ahead of the queue is reached by chance only |
| AC-06 | OK, proof incomplete | the same run: the header names `c4-infra.suite.queue`, `StartedAt`, `place in the queue`; CLAUDE.md the order and the place line; when a run tries the lock is read at `tests/lib/suite-lock.sh:15`, not checked |
| AC-07 | OK | Git Bash: the run above; Linux: `tests/0037-queue-linux.stand-in.sh` in the full run, `ok - tests/0037-queue.sh passes on the stand-in's Linux Docker`, `every check passed` |
| No regression | KO | the full run's FAILED list; 0019-collation this change's (frozen test), the five others pre-existing |

### Verification — c86531f (after the product owner's edits of the frozen test)

- The KO above is fixed: the product owner allowed the three edits of `tests/0037-queue.sh` (Deviations, 2026-10-30): `LC_ALL=C sort -n` at :122, CLAUDE.md in its `# covers:`, AC-06's header check naming "the run at place 1 tries the lock".
- Rerun of what changed since 9fd5d93: `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --changed 9fd5d93 --all` → `total: 61.1 s for 5 test(s)`, `verification passed (--changed: 5 of 81 tests)` (2026-10-30, `~/.cache/c4-infra-tests/0037-rerun.log`): `0019-collation`, `0037-queue` (50 `ok`), `0037-queue-linux.stand-in`, `0016-no-real-provider`, `0032-demo-github-only`. It waited in the queue for 0035's run (`waiting for the run of /d/workspaces/c4-infra-0035, started 2026-10-30 02:55:49`, `place in the queue: 1`), which held the lock through `main`'s library.
- Still open: the five pre-existing failures of the full run (none this change's); AC-05's proof reached by chance (the overtaking case).

| Criterion | Result | Evidence |
| --- | --- | --- |
| AC-06 | OK | the rerun: the header names `c4-infra.suite.queue`, `StartedAt`, "the run at place 1 tries the lock" (absent from `main`'s header), `place in the queue`; CLAUDE.md the order and the place line |
| No regression | OK for this change | `0019-collation`: `every check passed`; the five other failures of the full run fail the same way at `origin/main` |
- The product owner at delivery (2026-10-30): delivered in one batch with 0036 and 0035, after 0036; the batch's `bash tests/run.sh --all` before the push of `main`, accepted if its only failures are the five pre-existing ones. The change touches `CLAUDE.md`, the agent's configuration: the project has no evals (`git ls-files` names none), so no eval report. AC-05's proof stays reached by chance (the overtaking case).
