# Intent: tests/0049-docker-preflight.sh checks that the preflight reaped, never that it reaped before the tests

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: bug
- Source: 0051's review (2026-10-31: 0051's `plan.md`, Verification — cc9770d, "Pre-existing findings";
  drafted at the product owner's request in the skills' batch session)
- Spec needed: yes
- Status: accepted
- Opened: 2026-10-31
- Decided: 2026-10-31
- Supersedes: —
- Mode: bootstrap

## Problem

`tests/0049-docker-preflight.sh` proves 0049's AC-07 (no reaping or prune between the first test's start and
the last test's end, RQ-10: the reaper runs only from the preflight, before the first test) with two checks
on run E's logs. The first, `AC-07: the shim saw the preflight's reaping, before the tests`
(`tests/0049-docker-preflight.sh:268`), is `grep -q " ps -a --filter label=$NS.run " "$work/docker.log"`: it
finds the reaper's call (`docker_reap`'s `docker ps -a --filter "label=$ns.run"`,
`tests/lib/docker-preflight.sh:159`) anywhere in the log and never compares its time with the first test's
start. Both times are logged on the same clock: the shim writes `$(date +%s%N) <arguments>` per call (`:117`),
the fake tests `E start $(date +%s%N)` and `E end …` in `$work/order.log` (`:86`, `:90`, `:110`, `:112`);
the second check, `cleaning_during_tests` (`:191-197`, run at `:269-270`), does take its window from
`order.log`, but only flags a prune or removal in it, and the reaper's read lists nothing to remove in run E
(run B reaped first), so a reap during the tests passes it too.

- Steps: read the check at `:268`; or make run E reap during or after its tests (e.g. its fake holder test
  calls `docker_reap`, or `tests/run.sh` calls the preflight after its lanes).
- Expected: AC-07's first check is KO when the reaper's call comes after the first test's start.
- Observed (reading, 2026-10-31, a6e61c1): it passes as long as the call is anywhere in the log; the window
  check passes as long as nothing is removed.
- Environment: every system the suite runs on (bash on Ubuntu, Git Bash on Windows).

What it costs: the check's label says "before the tests" and its `ok` is read as proof of RQ-10's ordering;
a regression that moves the reaping into or after the tests (the risk 0049's RQ-10 guards against: a
cleaning while a test that measures time may run) passes the suite.

## Proposed outcome

AC-07's first check fails when the reaper's call is absent, or logged at or after the first test's start
(between tests, or after the last one), and passes when it comes before; the failure is proven by a
mutation; nothing else of the test is weakened.

## Affected users and systems

- Personas: Developer (the suite's verdict, which c4-infra's proofs rest on)
- Modules / systems: tests (`tests/0049-docker-preflight.sh`)

## Constraints

- The suite's rules: `# covers:`, `LC_ALL=C sort`, bash on Ubuntu and Git Bash on Windows (CLAUDE.md,
  "Repository layout" and "Verification"); a change of `tests/lib/` runs every test.
- Docker is shared on the workstation: the proof runs under the suite's lock, with 0049's label namespace
  (`C4_DOCKER_REAP=labelled`), touching nothing it didn't create.
- 0051's model: its window check is proven on planted logs, no Docker (`:199-206`).

## Open questions

- Compare by the shim's timestamps, as the window check does, or by an order that doesn't depend on a clock?
  — the product owner, at the spec.
