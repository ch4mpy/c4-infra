# Intent: A run waiting for the suite's lock can be overtaken by later runs, without bound

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: bug
- Source: conversation (2026-10-29, the verification of the skills' intent 0060)
- Spec needed: yes
- Status: accepted
- Opened: 2026-10-29
- Decided: 2026-10-29
- Supersedes: —
- Mode: bootstrap

## Problem

The suite's lock (`tests/lib/suite-lock.sh`, 0017's RQ-06) lets one run of `tests/run.sh` at a time
per Docker, the skills' suite included: the skills' `tests/run.sh` takes the same lock
(`c4-infra.suite-lock`) through its own copy of the script. A waiting run tries again every 2 s to
create the lock's container. When the holder ends, whichever waiting run tries first takes it,
whatever the order the runs started waiting in.

Observed on 2026-10-29, with several Claude sessions running suites on the workstation:

- a run of the skills' verifier for intent 0060, a test of one to two minutes, waited from 15:26;
- in that time, runs of the skills' worktrees 0083, 0065, 0074, 0072, a `before` run and 0076 (three
  times) took the lock before it;
- it took the lock at 16:09, only once the PO had asked another session to stop taking it.

The waiting run's only output names the current holder (`waiting for the run of …`): nothing says how
many runs are ahead, or that it is being overtaken. The 43 minutes of that wait delayed the delivery of
0060, and with it the demo deployment of Tickee, which waited for it. With more sessions running
suites, a waiting run has no bound.

## Proposed outcome

Runs take the lock in the order they started waiting for it, whichever repository they come from, and a
waiting run says its place in the queue.

Success criterion: with several runs waiting, each one starts in the order it arrived, and a waiting
run is never overtaken by a run that started waiting after it.

## Affected users and systems

- Developer, and the Claude sessions that run the suites on the workstation.
- The test suite (`tests/run.sh`, `tests/lib/suite-lock.sh`): *not declared in the project context*.
- The skills' suite (`~/.claude`, `tests/run.sh` and its copy of `tests/lib/suite-lock.sh`), which
  shares the lock.

## Constraints

- The lock is shared with the skills' suite: both copies follow the same protocol, and a run of one
  repository queues behind a run of the other.
- 0017's RQ-06: the lock is freed however its run ends; `docker rm -f c4-infra.suite-lock` frees one
  that hangs. A waiting run that is killed doesn't block the queue.
- `CLAUDE.md`: the scripts run under Git Bash on Windows and bash on Ubuntu.

## Open questions

- A twin intent in the skills' repository for its copy, or one change delivered in both? — the PO.
- May a short run (a verifier's single test) go ahead of a full suite? — the PO.
