# Spec: tests/0049-docker-preflight.sh checks that the preflight reaped, never that it reaped before the tests

- Intent: [0052](intent.md)
- Status: approved (2026-10-31)
- Version: 1
- Risk: standard (no risk rule applies: tests only; the preflight, the stack and what a host exposes don't change)
- Policies applied: none yet; standing constraints: CLAUDE.md "Repository layout" (bash and Git Bash) and "Verification" (`# covers:`, a change of `tests/lib/` runs every test, the suite's lock, the tests' Docker labels), 0049's RQ-10 and AC-07, 0051's RQ-04 (the window check proven on planted logs)
- Approved: —

## Summary

AC-07's first check of `tests/0049-docker-preflight.sh` says "before the tests" but only greps the reaper's call anywhere in run E's docker log. Once delivered, it compares each reaper call with the first test's start in `order.log`, as the window check already reads it, and is KO when the call is missing or comes at or after that start; the comparison is proven on planted logs (no Docker) and by a mutant whose reaping runs during the tests. For the Developer: the check's `ok` proves 0049's RQ-10 ordering, not just that a reap happened.

## Requirements

- **RQ-01:** AC-07's first check passes only when run E's docker log holds at least one reaper call (`ps -a --filter label=<ns>.run …`) and every such call is logged before the first test's start read from `order.log`; it is KO, its cause printed, when there is none, when one is logged at or after that start (between tests or after the last one), or when `order.log` holds no test start. (intent: proposed outcome; problem, `:268`)
- **RQ-02:** The comparison is proven on planted logs, no Docker, as 0051 proved the window check (`:199-206`): a reaper call before the planted start passes; one after the start, one after the planted end, a log without it and an order log without a start each fail. (intent: proposed outcome, "proven by a mutation"; constraint, 0051's model)
- **RQ-03:** A real-run mutant, used at verification and not kept in the suite, makes the reaping happen during run E's tests; AC-07's first check is then KO, while it is ok on the unmodified test. (intent: proposed outcome, "the failure is proven by a mutation")
- **RQ-04:** Nothing else of `tests/0049-docker-preflight.sh` is weakened: its checks and their labels (the first check's label may stay as is), the window check's behaviour and its three planted checks, the shim and its guard, its label namespace and `C4_DOCKER_REAP=labelled`, its runs A to E, its `# covers:` line; it runs under bash and Git Bash and sorts with `LC_ALL=C`. (intent: proposed outcome, "nothing else of the test is weakened"; constraints)

## Out of scope

- The preflight itself (`tests/lib/docker-preflight.sh`) and `tests/run.sh`: their order is right today (`docker_preflight` at `tests/run.sh:385`, before `in_lanes`/`in_turn` at `:388-391`); this change makes the test able to say so.
- What the window check flags (0049's matcher, kept by 0051): a read during the tests stays allowed.
- The other AC-07 and AC-09 checks, and other tests of the suite.

## Design

### Current behaviour

Read at a6e61c1 (the test not run):

- AC-07's first check: `check "AC-07: the shim saw the preflight's reaping, before the tests" grep -q " ps -a --filter label=$NS.run " "$work/docker.log"` (`tests/0049-docker-preflight.sh:268`): a match anywhere in the log; no time is read.
- The reaper's call: `docker ps -a --filter "label=$ns.run" --format …` in `docker_reap` (`tests/lib/docker-preflight.sh:159`), run by `docker_preflight` (`:303`) from `tests/run.sh:385`. No other call of run E matches: the fake holder's read is `ps -q --filter label=$NS.run` (`tests/0049-docker-preflight.sh:88`).
- The shim logs each call as `<date +%s%N> <arguments>` before it runs it (`:115-123`, the line at `:117`); the fake tests log `E start <date +%s%N>` and `E end …` in `$work/order.log` (`:86`, `:90`, `:102`, `:110`, `:112`): same clock, nanoseconds, comparable as numbers.
- The window check, `cleaning_during_tests` (`:191-197`, run at `:269-270`): takes the first `E start` and the last `E end` from `order.log` (`LC_ALL=C sort -n`), fails on a missing start or end (`BEGIN` rule), on a prune or removal logged in the window, or on no call in it. The reaper's `ps -a` is a read and lists nothing to remove in run E (run B reaped first, `:221-227`), so a reap in the window passes it; a reap after the last end is outside the window.
- So a preflight that reaped between two tests, or after the last one, passes both checks.

### Behaviour per persona

- **Developer**: `bash tests/0049-docker-preflight.sh` (under the suite's lock, on Linux and under Git Bash) passes when the preflight reaps before the first test, as today; a reap logged at or after the first test's start is a KO of `AC-07: the shim saw the preflight's reaping, before the tests`, printing the offending log line and the start it was compared with.

### API and contracts

- The test's check labels stay; RQ-02 adds planted checks (e.g. `AC-07: the reaping's check passes on a reap before the first test`, `… fails on a reap after the first test's start`, `… after the last test's end`, `… on a log without it`, `… on an order log without a start`). A KO prints its cause under it (`check`, `tests/lib/assert.sh`).

### User interface

None.

### Data

None.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| — | the project has no policy yet; CLAUDE.md's bash and Git Bash rule → RQ-04; the suite's Docker labels and lock → RQ-04 |

## Points of attention

### PA-01: How the reaper's call is ordered against the first test's start

- Issue: the check needs an order between two logs written by different processes (the shim, the fake tests); the window check already relies on their shared clock.
- Options: **A** reuse the window check's ordering: one function of the test (not `tests/lib/`) reads the first test's start (and the last end) from `order.log`, used by `cleaning_during_tests` and by the new check, which compares each reaper call's timestamp with it / **B** a separate timestamp comparison, the new check reading `order.log` on its own (a second copy of the first-start extraction) / **C** a sequence counter: the shim and the fake tests take the next number from a shared counter file instead of (or beside) the clock, so the order doesn't depend on `date +%s%N` (a change of the shim and of both fake tests, and a lock or atomic increment across lanes).
- Recommendation: A: one reading of "the first test's start" for both AC-07 checks, so they can't drift apart; the clock is already what the window check trusts, the same machine writes both logs, and the shim logs before it runs the call; C fixes a clock problem nobody has seen, at the cost of a concurrency mechanism in a test.
- Decides: PO
- Decision: A — the PO, 2026-10-31

### PA-02: Which reaper calls must precede the first test

- Issue: RQ-10 says the reaper runs only from the preflight, before the first test; the preflight calls it once, but a regression could add a reap during the tests while keeping the one before.
- Options: **A** every logged reaper call is before the first test's start, and there is at least one / **B** the first reaper call is before the first test's start (a reap added during the tests, beside the preflight's, still passes).
- Recommendation: A: it is what RQ-10 states, and it catches RQ-03's mutant (a reap during the tests added to the preflight's); no legitimate call of run E matches the reaper's pattern (`:88` is a `ps -q` without `-a`).
- Decides: PO
- Decision: A — the PO, 2026-10-31

### PA-03: The real-run mutation

- Issue: planted logs prove the comparison; only a run proves the check reads run E's real logs that way.
- Options: **A** planted checks in the test (RQ-02) and one real-run mutant at verification, a throwaway copy of the test whose run E fake holder test sources `tests/lib/docker-preflight.sh` and calls `docker_reap` (as 0051's AC-04 mutant, recorded in its plan's open questions) / **B** planted checks only.
- Recommendation: A: it costs one run of the test (about 20 s) at verification, nothing in the suite, and shows the KO on the path the bug describes; B leaves the wiring between the check and run E's logs unproven.
- Decides: PO
- Decision: A — the PO, 2026-10-31

## Acceptance criteria

- **AC-01:** Given the product owner's Linux workstation, under the suite's lock, when `bash tests/0049-docker-preflight.sh` runs, then every check passes, `AC-07: the shim saw the preflight's reaping, before the tests` included. (RQ-01, RQ-04)
- **AC-02:** Given the Windows workstation under Git Bash, when the same test runs, then every check passes. (RQ-01, RQ-04)
- **AC-03:** Given the planted order log `E start 100`, `E end 200`, when the reaping's check reads a planted docker log, then it passes on `50 ps -a --filter label=<ns>.run …` alone, and fails on a reaper call at 150, on one at 250, on `50` plus `150` (as PA-02 decides), on a log without a reaper call, and on an order log without a start; no Docker involved. (RQ-01, RQ-02)
- **AC-04:** Given a copy of the test whose run E fake holder test calls `docker_reap` during its run (PA-03), on Linux, when it runs, then `AC-07: the shim saw the preflight's reaping, before the tests` is KO and the test exits 1; on the unmodified test, ok. (RQ-03)
- **AC-05:** Given the change, when `bash -n tests/0049-docker-preflight.sh` and `bash tests/run.sh --changed` run, then both pass, and `git diff` of the test removes no check label, keeps `cleaning_during_tests`' three planted checks passing and its `# covers:` line unchanged. (RQ-04)

## Intent questions

- Compare by the shim's timestamps, as the window check does, or by an order that doesn't depend on a clock? → PA-01.

## Change log

- v1 — 2026-10-31 — first version
- v1 approved — 2026-10-31 — PA-01 to PA-03 decided A by the PO, also tech lead (bootstrap mode)
