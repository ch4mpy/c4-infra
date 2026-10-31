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

Bootstrap mode (intent home's `Mode` line): no PR, no stage label, gates decided in this session; the release gate does not hold pushes to `main`.

### Verification — 32a86dc

Machine: the product owner's Linux workstation (Ubuntu 26.04.1 LTS, Docker 29.x), locale `fr_FR.UTF-8`, the runs under `LC_ALL=C` (deviation above), `TMPDIR=/home/jerome/.cache/c4-infra-tests`.

- **KO first:** under `fr_FR.UTF-8`, `bash tests/0049-docker-preflight.sh` at 32a86dc → `4 check(s) failed` (`AC-09: the host's memory from MemAvailable (Linux)`, `AC-09: Docker's VM measured`, `AC-05: the shortage named`, `AC-09: the VM's disk read from df's line, what a pull prints first aside`), `exit 1`: 0050's decimal comma, pre-existing on `main`, not 0052's; the six planted reaping checks and `ok - AC-07: the shim saw the preflight's reaping, before the tests` ok under both locales.
- Red (step 1, 8869741, the planted checks alone, no Docker): `KO - AC-07: the reaping's check fails on a reap after the first test's start`, `… after the last test's end`, `… during the tests beside one before`, `… on an order log without a start`; `4 check(s) failed`, `exit 1`. Green (6174b65): the nine planted checks ok, `every check passed`, `exit 0`; `LC_ALL=C bash tests/0049-docker-preflight.sh` → `every check passed`, `exit 0` (19.6 s).
- Verification command: `LC_ALL=C C4_DOCKER_REAP=labelled bash tests/run.sh --changed` → `verification passed (--changed: 5 of 89 tests)`, `run.sh exit 0` (2026-10-31, 08:59), at 6174b65
- Rerun after the fixes: `LC_ALL=C C4_DOCKER_REAP=labelled bash tests/run.sh --changed 6174b65` → `verification passed (--changed: 4 of 89 tests)`, `run.sh exit 0` (09:02), at 32a86dc
- `bash -n tests/0049-docker-preflight.sh` → exit 0
- Durations: lock —, bugs review 2m06s @08:59, security review —, fix round 0m17s @09:02, run 0m23s @08:59, reruns 0m27s (first verdict —) @09:02, verifier 1m58s @09:04; total 6m25s (08:59–09:06)
- Risk tier: standard (tests only)
- Reviews: bootstrap mode: 1 round, on 546078e..6174b65 (/home/jerome/workspaces/c4-infra-0052); bugs (`code-review`, high): covered 546078e..6174b65, 0 Important, 7 details: 3 fixed (32a86dc), 4 answered; security and quality: not run (bootstrap, standard risk); the comments the diff adds read: one-line function headers and a section title, none says what the code does
  - fixed: the planted KO checks accepted any failure, not its cause (`tests/0049-docker-preflight.sh:225`): `reap_refused` now requires the printed cause; the reaper's pattern padded with spaces then trimmed for the message (`:213`): passed bare, padded in `index`; the no-start case duplicated `reap_planted`'s body in an `eval` (`:230`): `reap_planted` takes the order log
  - answered: only the reaper's container listing is compared, not its network, volume or image listings (`:214`): RQ-01 defines the reaper call as `ps -a --filter label=<ns>.run`, the first of `docker_reap`'s calls, which `docker_preflight` makes before the others in one function; "the first test's start" is the fake test's own `E start`, not `run.sh`'s lane setup (`:191`): the spec's definition (RQ-01, `order.log`), the same window the 0049 check reads; `window_edge` takes any word but `start` as `end` (`:193`): two callers, both literal; `reaped_before_tests` and `cleaning_during_tests` keep their own empty-edge guard (`:214`): PA-01 A shares the edge's reading, each check keeps its own causes
- Mutation check (bug): the planted checks at 8869741 (the pre-fix `grep -q` body) → `4 check(s) failed`, `exit 1` (this session and the verifier); the strengthened checks of 32a86dc against that body → `5 check(s) failed`, `exit 1`. AC-04's mutant (the Proof's `sed` command, run E's holder calls `docker_reap`) at 32a86dc → `KO - AC-07: the shim saw the preflight's reaping, before the tests`, `1793473421584709369 ps -a --filter label=c4-test-0049-859091.run --format … at or after the first test's start 1793473421358971654`, `1 check(s) failed`, `exit 1` (the window check ok, the reap removing nothing); the same rerun by the verifier, `exit 1`
- Verifier: 4/5 criteria OK, 0 KO — table below
- Not verifiable here: AC-02 (Git Bash on the Windows workstation): for the product owner, on that workstation (2026-10-31)
- Files outside the plan: none
- Pre-existing findings (not fixed, out of scope): none

| Criterion | Result | Evidence |
| --- | --- | --- |
| AC-01 | OK | `LC_ALL=C bash tests/0049-docker-preflight.sh` in the two `--changed` runs (6174b65, 32a86dc): `ok - AC-07: the shim saw the preflight's reaping, before the tests`, `ok - AC-07: no prune nor removal …`, `every check passed` |
| AC-02 | not verifiable | Git Bash on Windows: for the product owner's Windows workstation (2026-10-31): `bash tests/0049-docker-preflight.sh` → `every check passed`, with the six `ok - AC-07: the reaping's check …` lines and `ok - AC-07: the shim saw the preflight's reaping, before the tests` |
| AC-03 | OK | harness of the planted checks at HEAD (verifier): the six reaping checks and the window's three ok, `every check passed`, `exit 0`; each KO case asserts its cause (`… at or after the first test's start 100`, `no reaper call (…) logged`, `no test start logged`); at 8869741 the four misplaced or unordered cases KO |
| AC-04 | OK | the `docker_reap` mutant: `KO - AC-07: the shim saw the preflight's reaping, before the tests`, the call and the start printed, `exit 1`; ok on the unmodified test (AC-01) |
| AC-05 | OK | `bash -n` exit 0; both `--changed` runs `verification passed`, `run.sh exit 0`; `git diff 8912d88 -- tests/0049-docker-preflight.sh`: six check labels added, none removed, the first reaping check kept under its label, `# covers:` unchanged; the window check's three planted checks ok |

- Deployment: deploy-demo run 41232734143 on 3579d8b (the merge), `success` (both jobs: images, VPS); nothing the demo host runs changed, no check after deployment in this plan.
