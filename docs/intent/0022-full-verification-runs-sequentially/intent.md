# Intent: A full verification runs its stand-in tests one after the other, while nothing else runs

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: change
- Source: conversation (verification of 0017, 2026-10-28)
- Spec needed: yes
- Status: accepted
- Opened: 2026-10-28
- Decided: 2026-10-28
- Supersedes: —
- Mode: bootstrap

## Problem

`bash tests/run.sh --all`, the full verification, runs every test one after the other: about 55 minutes on 2026-10-28 (3273 s on 0017's head). Its nine `*.stand-in.sh` tests take 60 % of it (1947 s), each starting a stand-in demo host with its own Docker and deploying the stack there, while the dev stack's tests wait; the four facts tests take 12 % (386 s), the 31 others 28 % (917 s). The product owner runs it at each milestone (CLAUDE.md, 2026-10-28), and each one costs an hour of waiting.

## Proposed outcome

A full verification takes markedly less time than running its tests one after the other, with the same tests, the same checks and the same report (each test's duration, the slowest, the failed ones). Success criterion: `--all` on the same workstation takes at most two thirds of its time on 0017's head.

## Affected users and systems

- Personas: Developer (runs the verification)
- Modules / systems: the verification (`tests/run.sh`), the stand-in host (`tests/lib/stand-in-host.sh`)

## Constraints

- No test changes what it checks; a result must not depend on another test running at the same time.
- One run of the suite at a time per Docker stays (0017's lock).
- Docker Desktop on this workstation stopped starting containers once, under the suite's load (2026-10-27): the extra load is measured.

## Open questions

- Which tests may run at the same time (the stand-in ones with the dev stack's, as their Docker is their own; two stand-in hosts at once) — the spec, from measurements.
- *Suggested solution*: the stand-in tests in a lane of their own, beside the others — the spec.
