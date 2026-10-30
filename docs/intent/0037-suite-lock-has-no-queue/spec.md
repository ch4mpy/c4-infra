# Spec: A run waiting for the suite's lock can be overtaken by later runs, without bound

- Intent: [0037](intent.md)
- Status: approved
- Version: 1
- Risk: standard (no risk rule applies: the test tooling's lock on the workstation's Docker; no authentication, secret, isolation between applications, network exposure or personal data)
- Policies applied: none yet; standing constraints: 0017's RQ-06 and AC-06 (one run at a time per Docker, the lock freed however its run ends, `docker rm -f` frees it), CLAUDE.md (bash and Git Bash, a script with its test and its `# covers:`), the lock shared with the skills' suite (their copy of `tests/lib/suite-lock.sh`)
- Approved: 2026-10-29, Jérôme Wacongne (PO; in the drafting session, every point of attention decided)

## Summary

Runs waiting for the suite's lock form a queue on the Docker they share: each takes the lock in the order it started waiting, and says its place while it waits. A waiting run that ends leaves the queue. The lock itself doesn't change, so a run of a copy that doesn't queue yet (the skills' today) still never runs beside another, but can go ahead of the queue until that copy follows (PA-01). For the Developer and the Claude sessions: a wait bounded by the runs ahead, and known.

## Requirements

- **RQ-01:** A waiting run takes the lock only when no run that started waiting before it still waits: runs of this library take the lock in the order they started waiting, whatever their worktree. (intent: outcome, success criterion)
- **RQ-02:** A waiting run prints its place in the queue (`1` when it is next) when it starts waiting and each time the place changes; the line naming the holder stays as 0017 made it (`waiting for the run of <worktree>, started <date time>`). (intent: outcome, "says its place"; problem, nothing says how many runs are ahead)
- **RQ-03:** A waiting run that ends in any way (`kill -9`, interrupted, Ctrl-C) leaves the queue within 5 s: the runs behind it move up, none waits for it. (intent: constraint, "a waiting run that is killed doesn't block the queue")
- **RQ-04:** 0017's RQ-06 holds unchanged: one run at a time per Docker; the lock freed however its run ends; `docker rm -f c4-infra.suite-lock` frees a lock that hangs; a run that finds neither a holder nor a queue starts at once (within 10 s, 0017's AC-06). `SUITE_LOCK_NAME` names a queue of its own with its lock. (intent: constraint)
- **RQ-05:** The lock is taken as today (the container named `$SUITE_LOCK_NAME`, its labels), so a run of a copy that doesn't queue never runs beside a run that does, either way. (intent: constraint, the lock shared with the skills' suite)
- **RQ-06:** The library's header describes the protocol (what a waiting run creates in Docker, where the order comes from, when a run tries the lock), enough for another copy to follow it (PA-01). (intent: constraint, "both copies follow the same protocol")
- **RQ-07:** It works under Git Bash with Docker Desktop and under bash on Ubuntu. (intent: constraint, CLAUDE.md)
- **RQ-08:** CLAUDE.md's "Verification" says that waiting runs take the lock in the order they arrived and print their place. (intent: affected users, the Claude sessions that run the suites)

## Out of scope

- The skills' copy and their `tests/run.sh`: PA-01.
- A run's expected wait in time, a time limit on waiting, a priority for a short run (PA-02).
- Which runs take the lock (every c4-infra run that selects a test, the skills' runs with a slow test): unchanged.

## Design

### Current behaviour

- `suite_lock_take` (`tests/lib/suite-lock.sh:8-41`) tries every 2 s (`:39`) to start a container named `$SUITE_LOCK_NAME`, fed by a pipe from the run (`:14`); the run holds the lock once that container prints `held` (`:21`); `is already in use` means another run holds it (`:26`). Nothing records that a run waits: when the holder ends, whichever waiting run tries next takes the lock.
- A waiting run's only output is `waiting for the run of <worktree>, started <time>`, printed when the holder changes (`:36`); 0017's AC-06 checks it, anchored at the line's end (`tests/0017-run.sh:245-246`).
- `tests/run.sh:374` takes the lock before the first test of a run that selects one. The skills' `tests/run.sh:166-171` takes the same lock (`SKILLS_TESTS_LOCK`, default `c4-infra.suite-lock`) with their copy of the library (the same code under another header, `diff` on 2026-10-29), for a run with a test of their slow tier only.
- The incident of 2026-10-29 happened among the skills' runs: the waiting run (0060's verifier) and the runs that took the lock before it (worktrees 0083, 0065, 0074, 0072, a `before` run, 0076) were all the skills'. This change alone doesn't reach them: PA-01.

### Behaviour per persona

- **Developer, Claude sessions**: a run started while another holds the lock prints the holder as today, then `place in the queue: <n>`, and the new place whenever it changes; it starts when its turn comes. Stopping a waiting run (Ctrl-C, `kill`) moves the others up. Until the skills' copy follows (PA-01), a skills run can take the lock between two queued runs (RQ-05).

### API and contracts

- Waiting output: `waiting for the run of <worktree>, started <YYYY-MM-DD HH:MM:SS>` (unchanged, on a change of holder) and `place in the queue: <n>` (on a change of place). Nothing more once the run holds the lock.
- The protocol (RQ-06), as proposed here and measured by the plan: a waiting run starts a ticket container, fed by a pipe from the run as the lock is (so gone when the run ends however it ends, 0017's fact on that container), labelled with the lock's name, the run's worktree and its start; the order is Docker's record of each ticket's start, one clock for every client of that Docker (Git Bash, WSL, Ubuntu), ties broken by the container's id; a run tries the lock only while its ticket is the oldest, and drops its ticket once it holds the lock.

### User interface, Data

None: the tickets live in Docker only, as the lock does.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| — | No policy yet. Standing constraints: 0017's RQ-06 → RQ-04, AC-04; bash and Git Bash → RQ-07, AC-07; a script with its test and its `# covers:` → the tests of AC-01 to AC-05 cover `tests/lib/suite-lock.sh`; the lock shared with the skills → RQ-05, RQ-06, PA-01 |

## Points of attention

### PA-01: The skills' copy (the intent's first question)

- Issue: the overtaking seen on 2026-10-29 happened among the skills' runs, which take the lock through their own copy of the library. This change makes c4-infra's runs queue; until the skills' copy follows the same protocol, skills runs keep overtaking each other as before, and can take the lock ahead of c4-infra's queue (exclusion holds both ways, RQ-05).
- Options: A. This intent changes c4-infra only, its header stating the protocol (RQ-06); a twin intent in the skills' repository adopts it, drafted right after this spec's approval (it may choose to source c4-infra's file instead of keeping a copy). / B. One change delivered in both repositories: this intent's plan also changes the skills' copy, its header and a test of theirs, merged in both together.
- Recommendation: A. Each repository's changes start as its own intents (the skills' 0111, PA-01 C, did the same the other way), and the skills' `tests/run.sh`, its tiers and tests are theirs to change and prove. The twin is small: the library as c4-infra has it, and a test of the order among their runs. Cost: until the twin lands, the incident's case (skills runs among themselves) is unchanged.
- Decides: PO
- Decision: A, a twin intent in the skills' repository, drafted after this approval (2026-10-29, Jérôme Wacongne, PO)

### PA-02: A short run ahead of a full suite (the intent's second question)

- Issue: the run that waited 43 minutes was a verifier's test of one to two minutes, behind full suites. Letting a short run go ahead shortens such waits, but contradicts the intent's success criterion ("never overtaken by a run that started waiting after it") and needs every run to state its expected duration in the protocol.
- Options: A. Strict arrival order, no exception: the wait is bounded by the runs ahead, which the waiting run sees (RQ-02). / B. A run expected short (its tests' recorded durations under a bound, e.g. 5 minutes) goes ahead of the runs expected longer, a waiting run being overtaken a bounded number of times: a new intent, since it changes the accepted success criterion.
- Recommendation: A. It is the intent's criterion, simple enough for both copies to follow, and bounded. B needs both suites' duration records in the protocol and a bound to stay fair; if waits stay long once the queue exists, a later intent can add it, from measures.
- Decides: PO
- Decision: A, strict arrival order (2026-10-29, Jérôme Wacongne, PO)

## Acceptance criteria

- **AC-01:** Given a run A holding the lock and runs B, C and D of other worktrees started waiting in that order, when A ends, then B, C and D run in that order, each starting its first test after the previous one's last test ended. (RQ-01)
- **AC-02:** Given B, C and D waiting behind A, then B prints `place in the queue: 1`, C `place in the queue: 2` and D `place in the queue: 3`, each after the line naming A; when A ends, C prints `place in the queue: 1` and D `place in the queue: 2`. (RQ-02)
- **AC-03:** Given B and C waiting behind A, when B is killed with `kill -9` (in a second case, interrupted with Ctrl-C), then C prints `place in the queue: 1` within 5 s, and starts once A ends, without waiting for B. (RQ-03)
- **AC-04:** Given no run holding the lock and no queue, when a run starts, then it starts its first test within 10 s; `tests/0017-run.sh`'s AC-06 checks pass unchanged; two queues of different `SUITE_LOCK_NAME` don't see each other. (RQ-04)
- **AC-05:** Given a run queued behind A, when a run of the library as `main` has it today (no queue) takes the lock, then the two never hold it at once: the queued run starts its first test only after that run ended. (RQ-05)
- **AC-06:** Given the library's header and CLAUDE.md, then the header names what a waiting run creates in Docker, where the order comes from and when a run tries the lock, and CLAUDE.md's "Verification" names the order and the place line. (RQ-06, RQ-08)
- **AC-07:** Given Git Bash with Docker Desktop, then on a Linux Docker under bash (the Ubuntu workstation, or the stand-in host), the tests of AC-01 to AC-05 pass. (RQ-07)

## Intent questions

- A twin intent in the skills' repository for its copy, or one change delivered in both? → PA-01.
- May a short run (a verifier's single test) go ahead of a full suite? → PA-02.

## Change log

- v1 — 2026-10-29 — first version
- v1 — 2026-10-29 — approved in the drafting session: PA-01 A, PA-02 A
