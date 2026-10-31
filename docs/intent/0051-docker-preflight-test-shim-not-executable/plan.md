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

- 2026-10-31 — the Docker-backed proofs are not run in the implementing session: Docker is shared with another agent until later in the day — they wait for the orchestrator, once the machine is free: the test on Linux (AC-01), the mutations of AC-03 and AC-04, AC-05's real-run check (in AC-01's run), `bash tests/run.sh --changed` (AC-07), then the verification and its evidence in `## Verification`; AC-02 on the Windows workstation — run in the session without Docker: `bash -n` (ok), the test's Docker-free parts extracted into a scratch harness whose shim execs `/bin/true` (at 51cac50 the guard KO, `docker is /usr/local/bin/docker: the shim … is not found or not executable`, the three planted-line checks ok; at edef354 every check ok, `command -v docker` the shim), AC-06's searches (the spec's inventory, the 0049 shim now made executable at `:123`); shellcheck isn't installed — none on files or proof beyond the order in which they run.
- 2026-10-31 — AC-04's mutant, used when it runs: `printf '%s\n' 'sed -i "s/^\( *\)docker_reap /\1true /" "$repo/tests/lib/docker-preflight.sh"' > /tmp/no-reap.line && sed '/^cp tests\/lib\/\*\.sh /r /tmp/no-reap.line' tests/0049-docker-preflight.sh > tests/0051-mutant.sh && bash tests/0051-mutant.sh; echo "exit $?"; rm -f tests/0051-mutant.sh` (the throwaway repository's `docker_preflight` calls `true` instead of `docker_reap`, `tests/lib/docker-preflight.sh:303`; its AC-03 checks fail too, the reaping gone) — the *Proof* row of AC-04 points here instead of to *Verification*.
- 2026-10-31 — the verification's runs of `tests/run.sh` set `C4_DOCKER_REAP=labelled` (Docker shared with another agent: the preflight removes only what this run's namespace labelled) and `LC_ALL=C` (0050's decimal-comma bug, on `main`, fixed on 0050's branch, not delivered yet; not 0051's); CLAUDE.md's proof `bash tests/run.sh --changed --all` reduced to `--changed`: the change selects no stand-in or facts test.

## Verification

Bootstrap mode (intent home's `Mode` line): no PR, no stage label, gates decided in this session; the release gate does not hold pushes to `main`.

### Verification — cc9770d

Machine: the product owner's Linux workstation (Ubuntu 26.04.1 LTS, Docker 29.x), locale `fr_FR.UTF-8`, the runs under `LC_ALL=C` (deviation above).

- **KO first:** under `fr_FR.UTF-8`, `bash tests/0049-docker-preflight.sh` at 0d3abf9 → `4 check(s) failed` (`AC-09: the host's memory from MemAvailable (Linux)`, `AC-09: Docker's VM measured`, `AC-09: the VM's disk read from df's line, what a pull prints first aside`, `AC-05: the shortage named`): 0050's decimal comma, pre-existing on `main`, not 0051's; AC-07's checks ok under both locales.
- Verification command: `LC_ALL=C C4_DOCKER_REAP=labelled bash tests/run.sh --changed` → `verification passed (--changed: 5 of 89 tests)` (2026-10-31, 08:35), at 0d3abf9
- Rerun after the fixes: `LC_ALL=C C4_DOCKER_REAP=labelled bash tests/run.sh --changed 0d3abf9` → `verification passed (--changed: 4 of 89 tests)`, `run.sh exit 0` (08:41), at cc9770d
- `bash -n tests/0049-docker-preflight.sh` → exit 0
- Durations: lock —, bugs review 3m34s @08:37, security review —, fix round 0m17s @08:40, run 20.5 s (by the orchestrator, @08:35), reruns 0m34s (first verdict —) @08:41, verifier 2m47s @08:42; total 7m42s (08:37–08:44)
- Risk tier: standard (tests only)
- Reviews: bootstrap mode: 1 round, on c6a8872..0d3abf9 (/home/jerome/workspaces/c4-infra-0051); bugs (`code-review`, high): covered c6a8872..0d3abf9, 0 Important, 3 details: 2 fixed (cc9770d), 1 answered; security and quality: not run (bootstrap, standard risk); the comments the diff adds read: none says what the code does
  - fixed: the fake holder's header still said "nothing with Docker in run E" (`tests/0049-docker-preflight.sh:84`); the window check's `from == "" || to == ""` was a per-record rule, so an empty docker log named "no docker call" instead of "no test start or end logged" (`:194`, now a `BEGIN` rule; checked on scratch logs: empty order log → `no test start or end logged`, exit 1; empty docker log → `no docker call logged …`, exit 1; a read in the window → exit 0)
  - answered: the planted lines plant a `prune` only, not `rm`, `rmi`, `volume rm`, `network rm` (`:204-206`): the matcher is 0049's, unchanged; RQ-04 asks for a planted prune and an empty window, both proven
- Mutation check (bug), at cc9770d by the verifier, `LC_ALL=C C4_DOCKER_REAP=labelled`: AC-03's mutant (the `chmod` line removed) → `KO - AC-07: docker is the shim, and its calls are logged`, `docker is /usr/local/bin/docker: the shim …/shim/docker is not found or not executable`, `3 check(s) failed`, `exit 1`; AC-04's mutant (`docker_reap` → `true`, the second deviation) → `KO - AC-07: the shim saw the preflight's reaping, before the tests`, AC-03 ×4 KO, `5 check(s) failed`, `exit 1` (the same at 0d3abf9 by the orchestrator)
- Verifier: 6/7 criteria OK, 0 KO — table below
- Not verifiable here: AC-02 (Git Bash on the Windows workstation): for the product owner, on that workstation
- Files outside the plan: none (`spec.md`, the approved spec)
- Pre-existing findings (not fixed, out of scope): "the shim saw the preflight's reaping, before the tests" (`tests/0049-docker-preflight.sh:268`) greps the whole log and never compares the call's time with the first test's start, so its "before" is unchecked → bug intent suggested

| Criterion | Result | Evidence |
| --- | --- | --- |
| AC-01 | OK | `LC_ALL=C C4_DOCKER_REAP=labelled bash tests/0049-docker-preflight.sh` at cc9770d (verifier) and at 0d3abf9 (orchestrator): `ok - AC-07: docker is the shim, and its calls are logged`, `ok - AC-07: the shim saw the preflight's reaping, before the tests`, `every check passed`, exit 0 |
| AC-02 | not verifiable | Git Bash on Windows: to run on the product owner's Windows workstation |
| AC-03 | OK | the `chmod` mutant: the guard KO before run E naming the shim, `3 check(s) failed`, exit 1 |
| AC-04 | OK | the `docker_reap` → `true` mutant: `KO - AC-07: the shim saw the preflight's reaping, before the tests`, the guard ok, exit 1 |
| AC-05 | OK | `ok - AC-07: the window's check fails on a prune in it`, `… fails on a log with no call in it`, `… passes on a read in it`; the real run's `ok - AC-07: no prune nor removal …`; in AC-03's mutant the same check KO, `no docker call logged between the first test's start and the last test's end` |
| AC-06 | OK | the spec's four greps rerun: every stub run through `PATH` or `JAVA_HOME` made executable (`chmod +x`, `tests/lib/stubs.sh:39`, `tests/lib/argv-log.sh:19`, `install -m 0755`), the 0049 shim at `:123` |
| AC-07 | OK | `bash -n` exit 0; the two `--changed` runs above; `git diff df14155 -- tests/0049-docker-preflight.sh`: four check labels added (the guard, the three planted lines), none removed, `# covers:` and the namespace unchanged |
