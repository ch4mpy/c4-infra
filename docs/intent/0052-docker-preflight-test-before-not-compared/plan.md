# Plan: tests/0049-docker-preflight.sh checks that the preflight reaped, never that it reaped before the tests

- Spec: [v1](spec.md) (approved 2026-10-31, PA-01 A, PA-02 A, PA-03 A)
- Status: approved
- Branch: `0052-docker-preflight-test-before-not-compared` (worktree `/home/jerome/workspaces/c4-infra-0052`)
- Approved: 2026-10-31, Jérôme Wacongne (product owner, tech lead; bootstrap mode: "0052 tout A")

## Design

All in `tests/0049-docker-preflight.sh`; its `# covers:` line, label namespace, shim and guard, runs A to E and existing check labels unchanged (RQ-04).

- **One reading of run E's window (PA-01 A)**: a function `window_edge <start|end> <order log>` prints run E's first test start (`LC_ALL=C sort -n | head -n 1`) or last test end (`… | tail -n 1`) from `order.log`; `cleaning_during_tests` takes its `from` and `to` from it, its behaviour unchanged.
- **AC-07's first check (RQ-01, PA-02 A)**: a function `reaped_before_tests <order log> <docker log>`: with `from=$(window_edge start …)`, an `awk` that fails with `no test start logged` when `from` is empty (a `BEGIN` rule, as the window check's), prints each reaper call (a line holding ` ps -a --filter label=<ns>.run `) logged at or after `from`, followed by `at or after the first test's start <from>`, and fails with `no reaper call (ps -a --filter label=<ns>.run) logged` when there is none. The check at the former `:268` keeps its label and calls `reaped_before_tests "$work/order.log" "$work/docker.log"`.
- **Planted checks (RQ-02, AC-03)**, before any Docker run, on the planted order log `E start 100`, `E end 200` the window check already uses: a reap at 50 passes; one at 150, one at 250, 50 plus 150, a log with only the holder's `ps -q` read, and an order log with `E end 200` only each fail.

## Files

| File | Change | For |
| --- | --- | --- |
| `tests/0049-docker-preflight.sh` | modified: `window_edge`, `cleaning_during_tests` reading it, `reaped_before_tests`, its six planted checks, AC-07's first check calling it | RQ-01, RQ-02, RQ-04; AC-01 to AC-03, AC-05 |
| `docs/intent/0052-…/plan.md`, `intent.md`, `docs/intent/README.md`, `docs/intent/HANDOVER.md` | this plan, the intent's status, its index row, the handover at delivery | — |

## Order of work

1. **Failing test** — `reaped_before_tests` holding today's behaviour (`grep -q` of the reaper's call anywhere in the docker log, the order log unread), AC-07's first check calling it, the six planted checks — skill: none — check: `bash -n tests/0049-docker-preflight.sh`; the planted checks run alone (a scratch harness of the test's lines, no Docker): the four that expect a KO on a misplaced or unordered reap (150, 250, 50 + 150, no start) are KO, the two others ok — commit `test(0052): AC-07's reaping check on planted logs, before and after the first test`. The defect lives in the test itself, so the file can't be frozen: the next step's diff, `git diff HEAD~1 -- tests/`, touches the functions only, no planted check.
2. **Fix** — `window_edge`, `cleaning_during_tests` reading it, `reaped_before_tests`' comparison — skill: none — check: `bash -n`; the scratch harness: the six planted checks and the window check's three ok; then `LC_ALL=C bash tests/0049-docker-preflight.sh` → `every check passed` — commit `fix(0052): AC-07's reaping check compares each reaper call with the first test's start`.

## Risks

- The two logs' clock: the shim and the fake tests write `date +%s%N` on the same machine; the shim logs before it runs the call, so the preflight's reap is logged before `run.sh` starts a test. `awk` compares these 19-digit numbers as doubles (about 256 ns of resolution): two times that close compare equal, which the check reads as "at or after", a KO, never a false ok — the same reading the window check already trusts (PA-01 A).
- A legitimate call of run E matching the reaper's pattern → none: the holder's read is `ps -q` (no `-a`), the cleanup's `mine ps -a` runs after the check, outside the shim's `PATH`.
- Git Bash: `awk`, `sort -n` and `date +%s%N` already used by the window check there.

## Proof

| Criterion | How | Test, command or check |
| --- | --- | --- |
| AC-01 | automated test, Linux, under the test's own lock | `LC_ALL=C bash tests/0049-docker-preflight.sh`: `every check passed`, with `ok - AC-07: the shim saw the preflight's reaping, before the tests` |
| AC-02 | automated test, Windows Git Bash | the same command on the Windows workstation, by the product owner |
| AC-03 | automated checks (no Docker) | `ok - AC-07: the reaping's check passes on a reap before the first test`, `… fails on a reap after the first test's start`, `… fails on a reap after the last test's end`, `… fails on a reap during the tests beside one before`, `… fails on a log without it`, `… fails on an order log without a start`; at step 1, the four misplaced or unordered cases KO |
| AC-04 | mutation, Linux | `sed '/^  docker ps -q --filter "label=\$NS.run" > \/dev\/null$/a\  source tests/lib/docker-preflight.sh \&\& docker_reap > /dev/null' tests/0049-docker-preflight.sh > tests/0052-mutant.sh && LC_ALL=C bash tests/0052-mutant.sh; echo "exit $?"; rm -f tests/0052-mutant.sh` (run E's holder reaps during its run; `C4_DOCKER_REAP=labelled`, set by the test, keeps it to its namespace): `KO - AC-07: the shim saw the preflight's reaping, before the tests`, the call printed, `exit 1` |
| AC-05 | commands | `bash -n tests/0049-docker-preflight.sh`; `LC_ALL=C C4_DOCKER_REAP=labelled bash tests/run.sh --changed`: `verification passed`; `git diff 8912d88 -- tests/0049-docker-preflight.sh` removes no check label, keeps `# covers:`; the window check's three planted checks ok in AC-01's run |

## Deviations

- 2026-10-31 — the verification's runs set `LC_ALL=C` (0050's decimal-comma bug, on `main`, fixed on 0050's branch, not delivered yet; not 0052's; the test also run once under the machine's `fr_FR.UTF-8`, its known 0050 KOs recorded in *Verification*) and, for `tests/run.sh`, `C4_DOCKER_REAP=labelled` (Docker shared with another agent: the preflight removes only what this run's namespace labelled); CLAUDE.md's proof `bash tests/run.sh --changed --all` reduced to `--changed`: the change selects no stand-in or facts test.
- 2026-10-31 — the review round's fix (32a86dc) changes the six planted checks of step 1, which the plan said the fix wouldn't touch: each KO case now asserts the cause `reaped_before_tests` prints (`reap_refused`), and `reap_planted` takes the order log, so the no-start case reuses it; labels unchanged. A strengthening, not a weakening: against the pre-fix `grep -q` body, five of the six are KO (the "log without it" case too, which printed no cause); against the fix, all ok.

## Verification
