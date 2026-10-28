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
