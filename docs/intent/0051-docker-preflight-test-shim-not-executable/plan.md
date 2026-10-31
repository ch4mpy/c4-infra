# Plan: tests/0049-docker-preflight.sh's docker shim never runs on Linux, so its AC-07 checks prove nothing there

- Spec: [v1](spec.md) (approved 2026-10-31, PA-01 A, PA-02 A, PA-03 A)
- Status: approved
- Branch: `0051-docker-preflight-test-shim-not-executable` (worktree `/home/jerome/workspaces/c4-infra-0051`)
- Approved: 2026-10-31, Jérôme Wacongne (product owner, tech lead; bootstrap mode)

## Design

All in `tests/0049-docker-preflight.sh` (PA-01 A); its `# covers:` line, label namespace, runs A to E and existing check labels unchanged (RQ-06).

- **The fix (RQ-01)**: `chmod +x "$work/shim/docker"` right after the heredoc that writes it.
- **The guard (RQ-03)**: a function `shim_runs`, checked just before run E as `AC-07: docker is the shim, and its calls are logged`: in a subshell with `PATH="$work/shim:$PATH"` (an assignment, which also clears bash's command hash), `command -v docker` must print `$work/shim/docker`, else the KO says which `docker` was found and that the shim `$work/shim/docker` is not found or not executable; then `docker --version` (client only, no daemon) through it must append a ` --version` line to `$work/docker.log`, else the KO says the shim logged no call. The log is emptied after the guard, before run E.
- **A call during the tests (PA-02 A)**: the fake holder test, in run E, makes one harmless read between its start and end lines: `docker ps -q --filter "label=$NS.run" > /dev/null`.
- **AC-07's second check (RQ-04)**: `cleaning_during_tests <order log> <docker log>` takes its two files as arguments; besides the prune or removal it already reports, it fails with `no docker call logged between the first test's start and the last test's end` when the window holds none. Its matcher is proven before any Docker run on a scratch order log (`E start 100`, `E end 200`) and three planted docker logs: a `150 image prune -f` line in the window (KO expected), a single call outside it (KO expected), a single `150 ps -q …` in it (ok expected).

## Files

| File | Change | For |
| --- | --- | --- |
| `tests/0049-docker-preflight.sh` | modified: the shim made executable; the guard before run E; the holder's read in run E; `cleaning_during_tests` with arguments, its empty-window failure and its planted-line checks | RQ-01 to RQ-04, RQ-06; AC-01 to AC-05, AC-07 |
| `docs/intent/0051-…/plan.md`, `intent.md`, `docs/intent/README.md` | this plan, the intent's status, its index row | — |

## Order of work

1. **Failing test** — the guard, the holder's read, `cleaning_during_tests`' arguments and empty-window failure, the planted-line checks; no `chmod` yet — skill: none — check: `bash -n tests/0049-docker-preflight.sh`; on Linux the guard is KO (scratch run of `shim_runs` with the shim as the test writes it), the planted-line checks behave as expected (scratch run, no Docker) — commit `test(0051): the shim's guard and AC-07's non-vacuous checks`. The defect lives in the test itself, so the file can't be frozen: the next step's diff is the one `chmod` line, which `git diff HEAD~1 -- tests/` shows.
2. **Fix** — `chmod +x "$work/shim/docker"` — skill: none — check: `bash -n`; the scratch guard ok; on a free machine `bash tests/0049-docker-preflight.sh` under the lock — commit `fix(0051): make the docker shim of 0049's test executable`.
3. **Inventory (AC-06)** — rerun the spec's searches on the branch; a stub found without its execute bit is fixed here (RQ-05) — skill: none — check: the searches' output — no commit when nothing is found.

## Risks

- The holder's read and the guard's `--version` add calls to the shared Docker → both are reads (`--version` doesn't reach the daemon); `C4_DOCKER_REAP=labelled` and the namespace are unchanged.
- The honest run reveals a defect in the preflight or `run.sh` (AC-09's pull-lines check, AC-07's second check exercised on Linux for the first time) → PA-03 A: fixed here when small, with a spec v2; else a new bug intent.
- Git Bash: `command -v` prints the same `/tmp/…` form as `$work` there; the shim already ran there, `chmod` is harmless.

## Proof

| Criterion | How | Test, command or check |
| --- | --- | --- |
| AC-01 | automated test, Linux, Docker free | `bash tests/0049-docker-preflight.sh`: `every check passed`, with `ok - AC-07: docker is the shim, and its calls are logged` and `ok - AC-07: the shim saw the preflight's reaping, before the tests` |
| AC-02 | automated test, Windows Git Bash | the same command on the Windows workstation |
| AC-03 | mutation, Linux | `sed '/^chmod +x "\$work\/shim\/docker"$/d' tests/0049-docker-preflight.sh > tests/0051-mutant.sh && bash tests/0051-mutant.sh; echo "exit $?"; rm -f tests/0051-mutant.sh`: `KO - AC-07: docker is the shim, and its calls are logged`, naming the shim, `exit 1` |
| AC-04 | mutation, Linux | the copy whose throwaway repository's `docker_preflight` calls `true` instead of `docker_reap` (the command in *Verification*): `KO - AC-07: the shim saw the preflight's reaping, before the tests`, exit 1 |
| AC-05 | automated checks | the planted-line checks of the test (`AC-07: the window's check fails on a prune in it`, `… on a log with no call in it`, `… passes on a read in it`), and AC-07's second check ok in AC-01's run |
| AC-06 | command | `grep -rnB1 '^#!' tests/*.sh tests/lib/*.sh`, `grep -rnE "printf .*'#!" tests/`, `grep -rn 'PATH="\$' tests/`, `grep -rn chmod tests/`: every stub written then run through `PATH` or `JAVA_HOME` made executable |
| AC-07 | command | `bash -n tests/0049-docker-preflight.sh`; `bash tests/run.sh --changed`; `git diff df14155 -- tests/0049-docker-preflight.sh` keeps every former check label and the `# covers:` line |

## Deviations

<!-- filled during implementation: date — what — why — impact on files or proof -->
