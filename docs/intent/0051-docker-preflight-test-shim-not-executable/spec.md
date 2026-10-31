# Spec: tests/0049-docker-preflight.sh's docker shim never runs on Linux, so its AC-07 checks prove nothing there

- Intent: [0051](intent.md)
- Status: approved (2026-10-31)
- Version: 1
- Risk: standard (no risk rule applies: tests only; the preflight, the stack and what a host exposes don't change)
- Policies applied: none yet; standing constraints: CLAUDE.md "Repository layout" (bash and Git Bash) and "Verification" (`# covers:`, a change of `tests/lib/` runs every test, the suite's lock, the tests' Docker labels), 0049's RQ-10 and AC-07
- Approved: —

## Summary

`tests/0049-docker-preflight.sh` writes its `docker` shim without making it executable, so on Linux run E calls the real `docker`, the shim's log stays empty, AC-07's first check is KO and its second passes without testing anything. Once delivered, the shim runs on Linux and under Git Bash, the test says so before it reads the log, and AC-07's two checks fail when what they check is absent: a preflight that doesn't reap, a prune during the tests, a log with no call. For the Developer: the suite is green on Linux again, and its `ok` proves 0049's RQ-10 there. The grep of the suite finds no other stub in the same case; the scope (PA-01) is the product owner's choice.

## Requirements

- **RQ-01:** In run E, `docker` resolves to the test's shim and the shim runs, on Linux (bash on Ubuntu) and under Git Bash on Windows: each docker call of the run, the preflight's and the tests', is appended to its log. (intent: proposed outcome, "the shim runs and logs run E's docker calls")
- **RQ-02:** AC-07's first check ("the shim saw the preflight's reaping, before the tests") fails when the preflight doesn't reap: a run whose preflight skips its reaping gives a KO on Linux. (intent: proposed outcome, "a preflight that doesn't reap fails the first")
- **RQ-03:** Before run E, the test checks that `docker`, with the shim's folder first on `PATH`, is the shim and that a call through it reaches the log; otherwise a KO names it (the shim not found, not executable, or not logging), so that a shim that doesn't run is never read as an empty log. (intent: problem, "Git Bash runs the file anyway"; proposed outcome)
- **RQ-04:** AC-07's second check ("no prune nor removal between the first test's start and the last test's end") fails when the log holds no docker call made during the tests (as PA-02 decides), and when a prune or removal is logged in that window; its matcher is proven against a planted log line, no Docker involved. (intent: proposed outcome, "an empty log fails both")
- **RQ-05:** No other test of the suite runs, through `PATH`, a stub, shim or wrapper it wrote without making it executable: the inventory below is re-checked when the change is verified, and any file found in that case is fixed in this change. (intent: proposed outcome, "no other test of the suite relies on a stub written without being made executable"; open question)
- **RQ-06:** Everything else of `tests/0049-docker-preflight.sh` is as today: its checks and their labels, its label namespace and `C4_DOCKER_REAP=labelled` (nothing it didn't create is touched on the shared Docker), its runs A to E, its `# covers:` line; it runs under bash and Git Bash and sorts with `LC_ALL=C`. (intent: constraints)

## Out of scope

- The preflight itself (`tests/lib/docker-preflight.sh`), but a defect the honest test reveals (PA-03).
- 0050's locale defects (its own intent) and the pre-existing findings 0050's verification lists (`_docker_short` comparing rounded values, `df` and `/proc/meminfo` read several times).
- The fake tests `0001-holder.sh` and `0002-lane.stand-in.sh` this test writes (`:81`, `:106`), and those of `tests/0017-run.sh:46` and `tests/0022-lanes.sh:55`: `tests/run.sh` runs a test with `bash "$test"` (`:196`, lanes `:218`), not through `PATH`, so they need no execute bit.
- A shared helper or a suite-wide lint check, unless PA-01 B or C.

## Design

### Current behaviour

- The shim: `tests/0049-docker-preflight.sh:113-121`, `cat > "$work/shim/docker" << EOF`, a bash script that appends `<epoch in ns> <args>` to `$work/docker.log`, prints a pull's two lines on stderr for a `run … alpine:3`, then `exec`s the real docker (`REAL_DOCKER`, `:42`). `grep -n chmod tests/0049-docker-preflight.sh`: nothing. `bash -n`: ok.
- Run E: `: > "$work/docker.log"` (`:234`), `PATH="$work/shim:$PATH" suite E --all` (`:235`). In run E the fake tests make no docker call (the holder exits before Docker, `:87-91`; the lane test only sleeps, `:106-112`), so every logged call is the preflight's or `run.sh`'s.
- AC-07's first check: `grep -q " ps -a --filter label=$NS.run " "$work/docker.log"` (`:239`), the call of `docker_reap` (`tests/lib/docker-preflight.sh:133`, its `docker ps -a --filter "label=$ns.run"` at `:159`), which `docker_preflight` runs (`:303`) from `tests/run.sh:385`.
- AC-07's second check, `cleaning_during_tests` (`:240-247`): takes the window from `order.log`, prints the docker calls of `docker.log` inside it that prune or remove, and passes when there is none. An empty `docker.log` gives none: it passes.
- AC-09's check that the VM's disk is read past what a pull prints first (`:237-238`): the pull's lines come from the shim (`:117-119`); on Linux they are never printed, so the check exercises only the plain case.
- On Linux, bash's `PATH` lookup skips a file without the execute bit and finds the real `docker`; Git Bash runs it anyway (MSYS takes a file whose content starts with `#!` as executable), which is why 0049 passed on the Windows workstation.
- 0050's validation (its `plan.md`, Verification — dca25ea): `KO - AC-07: the shim saw the preflight's reaping, before the tests`, `1 check(s) failed`, at c6a8872 and dca25ea, under `fr_FR.UTF-8` and `LC_ALL=C`; a copy of the test keeping the log: 0 lines.

### The suite's stubs (RQ-05's inventory, 2026-10-31, c6a8872)

Files the suite writes, then runs through `PATH` (or `JAVA_HOME`), and where each is made executable:

| Written at | Made executable at |
| --- | --- |
| `tests/lib/stubs.sh:16`, `:22`, `:29` (`stub_path`: docker, getent, powershell.exe; used by 0001, 0002, 0003, 0004, 0009, 0011-up, 0012, 0012-themes-review, 0013, 0015, 0016) | `tests/lib/stubs.sh:39` |
| `tests/lib/argv-log.sh:14` (`argv_log_wrapper`; used by 0008) | `tests/lib/argv-log.sh:19` |
| `tests/0002-register-scope.sh:184` | `:200` |
| `tests/0003-up-reload.sh:20` | `:30` |
| `tests/0007-dev.sh:274` | `:283` |
| `tests/0011-scripts.sh:34`, `:58` | `:35`, `:59` |
| `tests/0011-up.sh:27` | `:45` |
| `tests/0012-themes-review.sh:134` | `:136` |
| `tests/0013-register.sh:121` | `:129` |
| `tests/0034-negative-checks.sh:87` | `:102` |
| `tests/0027-backup-facts.stand-in.sh:216`, `tests/0033-limits-facts.stand-in.sh:299` (inside a stand-in) | `chmod 0755` on the same line or the next |
| `tests/0002-accounts.stand-in.sh:327` (inside a stand-in) | `install -m 0755` on the same line |
| **`tests/0049-docker-preflight.sh:114`** | **nowhere** |

Found with `grep -rnB1 '^#!' tests/*.sh tests/lib/*.sh`, `grep -rnE "printf .*'#!" tests/`, the `PATH="$…"` prefixes of `tests/` and `grep -rn chmod tests/`. The 0049 shim is the only one.

### Behaviour per persona

- **Developer**: on Linux and under Git Bash, `bash tests/0049-docker-preflight.sh` (under the suite's lock) passes when the preflight reaps before the tests and nothing prunes during them; a shim that doesn't run is a KO naming it before run E; a preflight that doesn't reap, or a prune during the tests, is an AC-07 KO.

### API and contracts

- The test's check labels stay; RQ-03 adds one check before run E (e.g. `AC-07: docker is the shim, and its calls are logged`); RQ-04 may add one for the planted line. A KO prints its cause under it (`check`, `tests/lib/assert.sh`).

### User interface

None.

### Data

None.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| — | the project has no policy yet; CLAUDE.md's bash and Git Bash rule → RQ-01, RQ-06; the suite's Docker labels and lock → RQ-06 |

## Points of attention

### PA-01: How far the fix goes

- Issue: the omission is one line, but Git Bash hides the whole class: a stub written on the Windows workstation without the execute bit passes there and fails, or passes vacuously, on Linux. The inventory finds no other case today.
- Options: **A** fix 0049's shim alone (make it executable where it is written) with RQ-03's guard in that test / **B** A, and write 0049's shim with a shared helper of `tests/lib/` that always sets the bit (`argv_log_path` already logs and `exec`s the real command, but not the pull lines this shim prints: it would need an option), a change of `tests/lib/` that runs every test / **C** A, and a suite-wide read check (as `tests/0049-docker-labels.sh` reads every test for its labels) that every file a test writes into a folder it puts on `PATH` is made executable, a heuristic with its own false positives and misses.
- Recommendation: A: the inventory shows a single omission, the shared helpers already set the bit, and the guard makes this test's failure explicit on both systems; C stays available as its own intent if the class comes back.
- Decides: PO
- Decision: A — the PO, 2026-10-31

### PA-02: What makes AC-07's second check non-vacuous

- Issue: in run E the fake tests call no docker, so the window between the first test's start and the last test's end may truly hold no call: "no prune there" is then true of an empty log too.
- Options: **A** the fake holder test of run E makes one harmless, logged docker call during the window (a read, e.g. `docker ps -q --filter label=$NS.run`), the check requires at least one logged call in the window, and its matcher is proven against a planted `… image prune …` line in a scratch log (no Docker) / **B** the check fails only on an empty log, and its matcher is proven on a planted line / **C** nothing more: RQ-03's guard and the first check already fail on an empty log.
- Recommendation: A: it proves that a call made during the tests reaches the log, which is what the check relies on; B and C leave a log the shim fills before the tests only (a lane's `PATH` losing the shim) undetected.
- Decides: PO
- Decision: A — the PO, 2026-10-31

### PA-03: A defect the honest test reveals

- Issue: once the shim runs on Linux, AC-09's pull-lines check (`:237-238`) and AC-07's second check are exercised there for the first time; one of them may then fail on a real defect of the preflight or of `tests/run.sh`.
- Options: **A** fixed in this change when it is small and inside the preflight's parsing or `run.sh`'s lanes (a version 2 of this spec says so), a new bug intent otherwise / **B** always a new bug intent, this change delivering the honest test with its KO visible.
- Recommendation: A: the suite on Linux is the product owner's daily proof; leaving it KO for a small, now visible defect would hide the next one, which is this intent's cost.
- Decides: PO
- Decision: A — the PO, 2026-10-31

## Acceptance criteria

- **AC-01:** Given the product owner's Linux workstation, under the suite's lock, when `bash tests/0049-docker-preflight.sh` runs, then every check passes and run E's `docker.log` holds the preflight's `ps -a --filter label=<ns>.run` call. (RQ-01, RQ-02, RQ-06)
- **AC-02:** Given the Windows workstation under Git Bash, when the same test runs, then every check passes. (RQ-01, RQ-06)
- **AC-03:** Given a copy of the test whose shim isn't made executable, on Linux, when it runs, then RQ-03's check is KO before run E, naming the shim, and the test exits 1. (RQ-03)
- **AC-04:** Given a copy of the test whose throwaway repository's preflight library skips the reaping (the `docker_reap` call of `docker_preflight` removed), on Linux, when it runs, then AC-07's first check is KO and the test exits 1. (RQ-02)
- **AC-05:** Given AC-07's second check, when the log holds a prune or removal inside the window (a planted line), then it is KO; when the log holds no call in the window, then it is KO as PA-02 decides; on the real run, ok. (RQ-04)
- **AC-06:** Given the suite at the change's commit, when the inventory's searches are rerun, then every file a test writes and runs through `PATH` or `JAVA_HOME` is made executable, the 0049 shim included. (RQ-05)
- **AC-07:** Given the change, when `bash -n tests/0049-docker-preflight.sh` and `bash tests/run.sh --changed` run, then both pass, the test's other check labels and its `# covers:` line unchanged. (RQ-06)

## Intent questions

- Do other tests write a stub or shim they put on `PATH` without making it executable? → no: the inventory above (2026-10-31, c6a8872); AC-06 reruns it.
- Fix this test alone, or give the suite a way that makes the omission impossible or detected? → PA-01.

## Change log

- v1 — 2026-10-31 — first version
- v1 approved — 2026-10-31 — every point of attention decided A by the PO, also tech lead (bootstrap mode)
