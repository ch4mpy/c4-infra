# Plan: A full verification runs its stand-in tests one after the other, while nothing else runs

- Spec: [v1](spec.md)
- Status: approved
- Branch: 0022-full-verification-runs-sequentially
- Approved: 2026-10-28, Jérôme Wacongne (engineer; standard risk)

## Starting point

`bash tests/run.sh --all` runs its 44 tests one after the other: 3273 s on 0017's head, the 9 stand-in tests 1947 s, the 4 facts tests 386 s, the 31 others 917 s. Spec v1 (approved 2026-10-28): PA-01 B, three lanes (two stand-in hosts sharing the stand-in tests by duration, every other test in the third), PA-02 A (each test's output printed whole when it ends, a start line meanwhile), PA-03 A (Docker Desktop given at least 10 GiB; below it, one stand-in lane, said by the run). Target AC-01: `--all` ≤ 2182 s.

Facts read (2026-10-28):
- `tests/lib/stand-in-host.sh:36-47` already takes `STAND_IN_NAME` and `STAND_IN_VOLUME` from the environment (regex `^c4-infra-stand-in[a-z0-9-]*$`), two stand-ins never sharing a volume; no test writes the stand-in's name itself.
- What the stand-in tests share on the workstation's Docker: the stand-in host (name, volume); the image `c4-infra/stand-in-host`, which every stand-in test builds from the same context (`stand-in-host.sh:71`); the stack's images, read by `docker save` (`:99`). Only `0013-upgrade.stand-in.sh` builds an image of its own there (`c4-infra/keycloak:before`).
- Docker now reports 12536086528 bytes (Docker Desktop raised by the product owner, PA-03); 6144 MiB reported 6206390272.
- bash runs a test's EXIT trap on SIGTERM while it waits (`wait`), after the foreground command otherwise (measured): an interrupted lane's test gets TERM, and its stand-in host is removed so that its `docker exec` calls end.
- `tests/0017-run.sh` expects a run's test blocks in the suite's order, its `--all` runs included (`ran_exactly all.log …`): with lanes, a run with a stand-in test prints its blocks in the order they end (PA-02 A).

## Engineer's choices

- Lanes only when the selection holds a stand-in test (RQ-02); otherwise today's loop, untouched.
- The split by duration reads the durations of earlier runs, which every run records in the clone's common git directory (`c4-infra-test-durations`, one `<test> <microseconds>` line each, shared by its worktrees): longest first, each to the least loaded stand-in lane; a test with no recorded duration after them, alternating. No file of the repository changes between runs.
- Lane 1 is the default stand-in (`STAND_IN_NAME`, `STAND_IN_VOLUME`, or their defaults), lane 2 `<name>-2` and `<volume without -docker>-2-docker`; the third lane runs with no `STAND_IN_*` set, as today.
- Printing: the lanes write each test's output, start and end to a run directory; the run alone prints, polling it every second, so that two blocks never mix. The lanes keep the lock's pipe open (a run killed with `kill -9` still holds the lock until its lanes end: RQ-05), each test gets it closed (`{SUITE_LOCK_FD}>&-`), as in 0017.
- Docker's memory: two stand-in lanes when Docker reports at least 9 GiB (what 10 GiB given to Docker Desktop reports), else one, with `== Docker has <n> GiB, under the 10 GiB two stand-in lanes need (CLAUDE.md): one stand-in lane`. `SUITE_DOCKER_MEMORY` (bytes) replaces the measure: a test seam, as `REGISTRY_FILE` is.
- Interrupt (INT, TERM): TERM to each lane's running test, then the lanes' stand-in hosts removed (`docker rm -f`), exit 130.

## Files

| File | Change | For |
| --- | --- | --- |
| `tests/run.sh` | modified: the selected tests split into stand-in tests and others; with stand-in tests, one or two stand-in lanes (memory) and the others' lane, run in the background; the split by recorded durations; the start line `== <test> started (lane <n>), its output in <file>`; each test's block (`== <test>`, its output, `-- <test>: <s> s`) printed whole when it ends; durations recorded; the interrupt; the total, the slowest, `FAILED:` and the last line as today | RQ-01 to RQ-05 |
| `tests/0022-lanes.sh` | new: `run.sh` on a throwaway git repository (as `tests/0017-run.sh`), fake tests that print several lines with pauses, fake stand-in tests that start a container named `$STAND_IN_NAME` (alpine, `sleep`) and say their lane's name and volume; `STAND_IN_NAME` and `SUITE_LOCK_NAME` of its own | AC-02 to AC-06 |
| `tests/0017-run.sh` | modified: its runs with a stand-in test (`--all`, `--all --changed`) compare the set of tests run and the suite's order within the others' lane, instead of the whole order (the blocks now come as tests end) | RQ-03 (0022), 0017's AC-02 and AC-05 kept |
| `CLAUDE.md` | modified: "Verification": the lanes, the 10 GiB, the start lines, the durations file | RQ-06 |
| `docs/intent/0022-…/plan.md`, `intent.md`, `docs/intent/README.md` | this plan; status planned, then delivered; the index row | — |

## Order of work

0. **Setup**: on `0022-full-verification-runs-sequentially`, `git merge origin/main`; Docker reports ≥ 9 GiB. — skill: none — check: `git status --short` empty, `docker info --format '{{.MemTotal}}'` ≥ 9663676416.
1. **Facts**: two stand-in hosts side by side: `STAND_IN_NAME=c4-infra-stand-in-2 STAND_IN_VOLUME=c4-infra-stand-in-2-docker bash tests/0012-themes.stand-in.sh` started together with `bash tests/0003-demo-deploy.stand-in.sh` (`LC_ALL=C`, 0019 not delivered), a sampler writing the sum of `docker stats --no-stream` every 10 s; written into `tests/0022-lanes.sh`'s header. — skill: none — check: both pass, the peak memory recorded; a failure or a peak above 80 % of Docker's memory is a deviation (one stand-in lane, the engineer asked).
2. **`run.sh`'s lanes** and `tests/0022-lanes.sh`; `tests/0017-run.sh`'s expectations. — skill: none — check: `bash tests/0022-lanes.sh && bash tests/0017-run.sh`, then `bash tests/run.sh --changed HEAD~1` (run.sh changed: every test of the plain run, sequential, `verification passed`).
3. **Docs**: CLAUDE.md "Verification". — skill: none — check: `grep -n 'lane\|10 GiB' CLAUDE.md`; reread against RQ-06.
4. **Verification**: `LC_ALL=C TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --all` with the memory sampler: ≤ 2182 s, every test once (the set compared with 0017's proof run), the peak memory; mutation check: `tests/run.sh` of `main` → `tests/0022-lanes.sh` `KO`; then `/sdlc-verify 0022` (bootstrap: one round), its evidence into `## Verification`. — skill: sdlc-verify — check: the run's last line and duration.

## Risks

- Docker Desktop stalls under two stand-in stacks (it stopped starting containers once, 2026-10-27) → step 1 measures the peak first; the memory check picks one stand-in lane below 9 GiB; `SUITE_DOCKER_MEMORY=0` forces it by hand.
- Two lanes build `c4-infra/stand-in-host` at the same time → same context, same image; step 1 runs two stand-in tests together, which do it.
- A test of the others' lane and a stand-in test meet on the workstation's Docker (the stack's images rebuilt by `up.sh` while a stand-in test runs `docker save`) → `up.sh` rebuilds only what changed, nothing changes during a run; the proof run is the check.
- The others' lane becomes the longest (about 1300 s) → AC-01's target has 880 s of margin; the durations printed show where.
- The run directory and the durations file are new local state → the run directory is under `TMPDIR`, removed at the end; the durations file is one line per test in the git directory, never committed.
- A flaky pre-existing test (0021, 0020) fails the proof → noted as in 0017's evidence, the run's duration still measured.

## Proof

| Criterion | How | Test, command or check |
| --- | --- | --- |
| AC-01 | command | step 4: `LC_ALL=C TMPDIR=… bash tests/run.sh --all` → `total: … s`, at most 2182 s; the tests run, compared with 0017's proof run (the same 44, plus `0022-lanes`), each once |
| AC-02 | automated test | `tests/0022-lanes.sh`: two lanes' fake tests printing between pauses: each block from `== <test>` to `-- <test>: <s> s` holds only that test's lines; the start lines; the total and the slowest |
| AC-03 | automated test | `tests/0022-lanes.sh`: a fake stand-in test fails: the others' lane's tests all run, `FAILED:` lists it, exit 1 |
| AC-04 | automated test | `tests/0022-lanes.sh`: a plain run and a `--changed` run without a stand-in test print no start line and run in the suite's order; `tests/0017-run.sh` passes |
| AC-05 | automated test | `tests/0022-lanes.sh`: a second run started during a run with lanes waits until both lanes have ended; an interrupted run (SIGINT to its process group) leaves no fake test running |
| AC-06 | automated test | `tests/0022-lanes.sh`: each fake stand-in test says its lane's name and volume (two different ones); no container of those names after a run that passes, one that fails, one interrupted; the split follows the recorded durations |
| AC-07 | command + review | `grep -n 'lane\|10 GiB' CLAUDE.md`; "Verification" reread against RQ-06 |

## Deviations

<!-- filled during implementation: date — what — why — impact on files or proof -->

- 2026-10-28 — step 1: `0003-demo-deploy.stand-in` (123 s) and `0012-themes.stand-in` (298 s, its new volume pulling its images) passed at once on two stand-in hosts beside the dev stack; the sum of `docker stats` peaked at 6000 MiB, 50 % of Docker's 11955 MiB (written into `tests/0022-lanes.sh`'s header). Step 2: `tests/0017-run.sh` also gets stand-in names of its own (`STAND_IN_NAME`, `STAND_IN_VOLUME`), its `--all` runs now having a stand-in lane that would otherwise use the default host's name. No impact on proof.
- 2026-10-28 — the review's fixes (c40c5fc) and the verifier's (this commit's parent): a test never run before counts as the average of the recorded stand-in durations (a second when none), not "alternating" as *Engineer's choices* said (alternating ignored the load and could leave a lane empty, `members[3]` unbound); the memory message reads `== Docker reports <n.n> GiB, under the 9 GiB of Docker Desktop given 10 GiB, which two stand-in lanes need (CLAUDE.md): one stand-in lane` (6 GiB showed as 5); each lane test runs in a process group of its own (`set -m`), its stdin `/dev/null`, and Ctrl-C, TERM or a hangup sends TERM to its group (a closed terminal left the tests running after the lock was released), the run waiting 30 s at most for them and removing the stand-in hosts before and after; a lane gone before its tests end fails them (`no result, its lane ended before it`) instead of waiting for ever; a lane starts no test once the run is gone (kill -9); a failed test's duration isn't recorded; `lane<k>.pid` is removed once its test ends. Impact: `tests/0022-lanes.sh` checks each one (counter-proofs: 9 KO with b677cdf's run.sh, 2 with c40c5fc's); the durations file still held 0013-mcp's 5.6 s from b677cdf's failed run during the proof.

## Verification

### Verification — a4d8bd6

- Verification command: `LC_ALL=C TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --all` → `verification passed` (2026-10-28, on e01a97e, which adds only `plan.md` to a4d8bd6): `total: 1322.3 s for 45 test(s)`, run in 1323 s; every test once (0017's 44 and `0022-lanes`); 36 tests in lane 1, 4 on `c4-infra-stand-in`, 5 on `c4-infra-stand-in-2`; Docker's memory peak 7750 MiB, 65 % of 11955 MiB; no stand-in host left. CLAUDE.md's proof, `--changed --all`, runs the same set (`tests/run.sh` changed). Before: the sequential `--all` on 0017's head, 3273 s; with lanes on b677cdf (before the review) 1656 s, `FAILED: tests/0013-mcp.stand-in.sh` (its stand-in image build: `lookup registry-1.docker.io on 127.0.0.53:53: server misbehaving`, the workstation's resolver); on c40c5fc (the review's fixes) 1477 s, `verification passed`.
- Risk tier: standard (spec)
- Reviews: bootstrap mode: 1 round; bugs (`code-review`, high): 10 findings, 9 fixed in c40c5fc, 1 answered; no security pass (standard risk), no quality pass (bootstrap mode)
  - fixed: Ctrl-C left a lane test's foreground commands running and released the lock (each test in a process group of its own, `TERM` to the group, the run waiting 30 s at most); after `kill -9`, the lanes went on with their tests (none starts once the run is gone); a test never run before always went to lane 2 and could leave lane 3 empty, `members[3]` unbound (the average of the known durations, the least loaded lane); a lane gone before its tests' ends hung the run (they fail, `no result, its lane ended before it`); a test forked as its lane stopped escaped the interrupt (a second `TERM` pass, the hosts removed again after the wait); a failure's duration skewed the next split (not recorded); a memory value not a number kept two lanes, and 6 GiB showed as 5 (checked, one decimal); `tests/0022-lanes.sh` couldn't see a foreground command outliving an interrupt (its fake tests' commands now in the foreground, checked); the magic numbers (`GIB`, `TWO_STAND_IN_LANES_MEMORY`) and the lane's test command written twice (`env`)
  - answered: `ran_set` stays in each of the two tests rather than in `tests/lib/`: a test's helpers live in it, and a `tests/lib/` change runs every test
- Verifier: 5/7 criteria OK, AC-01 pending (since: the run above), AC-03's proof KO (the behaviour right), and an Important finding; fixed in 990262d:
  - a hangup (the terminal or ssh session closed) left the lanes' tests running after the lock was released, a regression from `main` (the verifier measured it under a pty): `HUP` is trapped as `INT` and `TERM`, checked by `tests/0022-lanes.sh`
  - AC-03's proof: `FAILED:` lists the failed test alone, every other test ran to its end, no `no result`; a block's end names its test and duration; an ended test's pid file removed; the shadowed `took` renamed; CLAUDE.md's "about an hour" (now half an hour); the test's header says Git Bash isn't measured
- Mutation checks: `tests/0022-lanes.sh` with `main`'s run.sh → `17 check(s) failed` (verifier); with b677cdf's → 9 `KO`, one per review fix; with c40c5fc's → `KO - AC-05, a hangup: no test of any lane goes on`, `KO - AC-06: no stand-in host left after a hangup`
- Not verifiable here: Git Bash (`set -m`, `kill -- -<group>`, Ctrl-C in a Windows console): the workstation is Linux
- Files outside the plan: none
- Pre-existing findings (not fixed, out of scope): the workstation's resolver failing once (above) → with 0020

| Criterion | Result | Evidence |
| --- | --- | --- |
| AC-01 | OK | the verification command above: 1323 s, at most 2182 s; the same 44 tests as 0017's proof and `0022-lanes`, each once |
| AC-02 | OK | `tests/0022-lanes.sh` → `ok - AC-02: each test's output whole, between its own lines` (each block ending with its own test's duration), the start lines, `the total, then the slowest`, `its last line`; the run above, block by block |
| AC-03 | OK | `tests/0022-lanes.sh` → `ok - AC-03: FAILED lists it alone`, `every other test ran to its end, in the other lanes as in its own`, `no test left without a result` |
| AC-04 | OK | `tests/0022-lanes.sh` → `ok - AC-04: plain: no start line`, `--changed without a stand-in test: no start line`; `tests/0017-run.sh` → `every check passed`; step 2: `bash tests/run.sh --changed HEAD` → `verification passed (--changed: 32 of 45 tests)`, one test after the other |
| AC-05 | OK (Linux) | `tests/0022-lanes.sh`: the next run waits until the last lane's end, after a run that ended and one killed with `kill -9`; interrupted and hung up: `no test of any lane goes on`; the verifier's Ctrl-C under a pty: `test processes left: none`, `lock gone` |
| AC-06 | OK | `tests/0022-lanes.sh`: two hosts, their own names and volumes, `no stand-in host left` after a run that passed, failed, was interrupted, hung up; the run above: `no stand-in left` |
| AC-07 | OK | CLAUDE.md:19 (the lanes, the two hosts, the durations file, the start lines, Ctrl-C, the 10 GiB), :15 (half an hour) |

