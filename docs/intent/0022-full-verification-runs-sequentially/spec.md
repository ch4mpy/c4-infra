# Spec: A full verification runs its stand-in tests one after the other, while nothing else runs

- Intent: [0022](intent.md)
- Status: approved
- Version: 1
- Risk: standard (no risk rule applies: the change touches the verification only)
- Policies applied: none yet; standing constraints: CLAUDE.md "Verification", 0017's spec (the lock, the selection, the report)
- Approved: 2026-10-28, Jérôme Wacongne (product owner, and tech lead for PA-01; in the drafting session; every point of attention decided)

## Summary

A run that includes stand-in tests runs them in lanes of their own, beside the other tests, instead of after them one by one; a run without stand-in tests is unchanged. The same tests run, once each, with the same checks; the report keeps each test's output whole, its duration, the slowest and the failed ones. Target: `--all` in at most two thirds of its sequential time.

## Requirements

- **RQ-01:** A run whose selection holds stand-in tests runs them beside the other tests, in the lanes PA-01 decides, so that `--all` on the same workstation takes at most two thirds of its sequential time. (intent: success criterion)
- **RQ-02:** Every selected test runs exactly once, with the same checks; the selection of each option (plain, `--all`, `--changed`) is unchanged; a run without stand-in tests runs its tests one after the other, as today. (intent: constraint, no test changes what it checks)
- **RQ-03:** The report keeps what 0017 gives: each test's output, then its duration, the total and the slowest at the end, `FAILED:` and the failed tests with exit 1, or `verification passed`. A test's output is printed as PA-02 decides, never mixed with another test's. (intent: outcome, the same report)
- **RQ-04:** No test's result depends on another one running at the same time: two tests that share a resource (a stand-in host, its volume, a container or network name) never run together. (intent: constraint)
- **RQ-05:** 0017's lock holds the whole run: a second run waits until every lane of the first has ended. Interrupting the run (Ctrl-C) stops every lane's test. (intent: constraint)
- **RQ-06:** CLAUDE.md "Verification" says how a run is laid out and what the workstation needs for it (PA-03). (intent: affected systems)

## Out of scope

- Making any test faster, or changing what it checks.
- Running the dev stack's tests at the same time as each other: they share the stack.
- A plain run or a `--changed` run without stand-in tests: unchanged.

## Design

### Current behaviour

- `tests/run.sh` runs the selected tests one after the other (0017). `--all` on 0017's head: 3273 s for 44 tests; the 9 stand-in tests 1947 s (60 %, from 118 s to 410 s each), the 4 facts tests 386 s, the 31 others 917 s.
- A stand-in test starts a privileged container with its own Docker, `c4-infra-stand-in`, whose `/var/lib/docker` is the volume `c4-infra-stand-in-docker` (the pulled images kept between runs); `STAND_IN_NAME` and `STAND_IN_VOLUME` already name another one beside it, two stand-ins never sharing a volume (`tests/lib/stand-in-host.sh:36-45`). It loads the stack's images from the workstation's Docker (`docker save | docker load`).
- Docker Desktop's VM on this workstation: 16 CPUs, 6144 MiB (the workstation: 29 GiB, 11 available); the dev stack with Faito's and immo's containers uses 1.8 GiB idle; a stand-in runs a second shared stack (Keycloak 0.7 GiB, Grafana LGTM 0.8 GiB idle on the dev stack). Docker Desktop stopped starting any container once during a run (2026-10-27, cause unknown).

### Behaviour per persona

- Developer: `bash tests/run.sh --all` takes markedly less time; while it runs, a line says when each test starts and in which lane; each test's output comes whole, then its duration.

### API and contracts

- `bash tests/run.sh [--all] [--changed [<base>]]`: options, selection, exit status and last line unchanged (0017).

### Data

None.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| CLAUDE.md "Verification" | RQ-02 (the same tests and options), RQ-06 (the layout and its needs documented) |
| 0017's lock (RQ-06 of 0017) | RQ-05 |

## Points of attention

### PA-01: The lanes

- Issue: the stand-in tests (60 % of `--all`) are the longest lane whatever the layout; one stand-in lane only just meets the target.
- Options: A) two lanes: the stand-in tests in one, every other test in the other; expected about 1950 s (60 %) before any slowdown from the shared load, close to the 67 % target / B) three lanes: the stand-in tests split by duration between two stand-in hosts (each its own name and volume, the second volume pulling its images once), every other test in the third; expected about 1300 s (40 %), the other lane being the longest / C) A, then B only if A misses the target when measured.
- Recommendation: B: it meets the target with a margin, and the second volume's first pull is paid once; it needs the memory of PA-03.
- Decides: tech lead
- Decision: B, three lanes (Jérôme Wacongne, tech lead, 2026-10-28)

### PA-02: A test's output while lanes run

- Issue: two tests running at once would mix their lines.
- Options: A) each test's output kept aside and printed whole when it ends, a line `== <test> started (lane <n>)` when it starts, naming where its output is kept meanwhile / B) printed live, each line prefixed with its test's name, mixed with the other lane's.
- Recommendation: A: the report reads as today's, test by test; a hanging test's output can still be read where it is kept.
- Decides: PO
- Decision: A, each test's output whole when it ends (Jérôme Wacongne, PO, 2026-10-28)

### PA-03: Docker Desktop's memory

- Issue: two stand-in stacks beside the dev stack and the facts tests' throwaway Keycloaks don't fit in 6144 MiB with room to spare; Docker Desktop is a workstation setting, outside the repository.
- Options: A) the workstation gives Docker Desktop at least 10 GiB (CLAUDE.md says so; the run warns below it) / B) 6144 MiB kept, PA-01 A only.
- Recommendation: A, with B's layout when it has less (the run picks it and says so): this workstation can spare it.
- Decides: PO
- Decision: A, at least 10 GiB, B's layout below it, said by the run (Jérôme Wacongne, PO, 2026-10-28)

## Acceptance criteria

- **AC-01:** Given this workstation, the dev stack up and Docker Desktop's memory per PA-03, when `bash tests/run.sh --all` runs on this change's head, then it takes at most 2182 s (two thirds of 3273 s) and runs the same tests as the sequential run, each once. (RQ-01, RQ-02)
- **AC-02:** Given a run with stand-in tests, then each test's output is printed as PA-02 decides, never mixed with another's, followed by its duration; the run ends with the total, the slowest, and `FAILED:` or `verification passed` as today. (RQ-03)
- **AC-03:** Given a test that fails in one lane, then the other lanes go on, and the run lists it under `FAILED:` and exits 1. (RQ-03)
- **AC-04:** Given a plain run, or a `--changed` run that selects no stand-in test, then its tests run one after the other, as before. (RQ-02)
- **AC-05:** Given a run with lanes in progress, when a second run starts, then it waits until every lane of the first has ended; given the first interrupted (Ctrl-C), then no test of any lane goes on. (RQ-05)
- **AC-06:** Given two stand-in lanes, then each stand-in host has its own name and volume, and none of them runs once the run has ended, passed, failed or interrupted. (RQ-04)
- **AC-07:** Given CLAUDE.md, then "Verification" says how the run lays out its lanes and the memory it needs. (RQ-06)

## Intent questions

- Which tests may run at the same time → PA-01 (the stand-in ones beside the others; two stand-in hosts with their own names and volumes), RQ-04.
- *Suggested solution*: the stand-in tests in a lane of their own → PA-01.

## Change log

- v1 — 2026-10-28 — first version; approved: PA-01 B, PA-02 A, PA-03 A
