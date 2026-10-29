# Intent: A demo host backup cut by its time limit may leave its dump running, a restore has no time limit, and four backup paths are untested

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: bug
- Source: conversation (0027's verifier and review round, 2026-10-28)
- Spec needed: yes
- Status: delivered (2026-10-28)
- Opened: 2026-10-28
- Decided: 2026-10-28
- Supersedes: —
- Mode: bootstrap

## Problem

`sudo c4-app backup` (intent 0027) bounds each item: `timeout 1800` around `docker exec <db> pg_dump …` (`demo/c4-app:658`). `docker exec` forwards no signal to the process it started: when the time limit cuts the CLI, `pg_dump` may go on in the application's database container, holding its locks, after `c4-app` has refused the backup and released the application's lock. `sudo c4-app restore` has no time limit at all (its checks, `DROP`/`CREATE`, `pg_restore`, `tar -x`), so one stuck restore holds the application's lock until someone notices. And four paths of 0027's review round are read in the code but tested by nothing: the time limits, a service labelled `volumes` that mounts no named volume (refused), a volume shared by a `postgres` and a `volumes` service, and the restart order over several `depends_on` layers. No application uses the backups yet; Tickee would be the first.

- Expected: a backup or a restore that exceeds its time limit leaves nothing running on its behalf, says so, and frees the application's lock; each of these paths is held by a test.
- Observed: not reproduced yet (read in the code, `docker exec`'s documented behaviour); the four paths untested.

## Proposed outcome

On the demo host, a backup or restore cut by its time limit stops what it started, in the application's containers too, and reports it; a restore has a time limit; the four paths have stand-in tests, so that a later change of `c4-app` can't break them unnoticed.

## Affected users and systems

- Personas: Application (its data, its lock); Demo operator
- Modules / systems: demo host (`demo/c4-app`), tests (stand-in)

## Constraints

- 0027's guarantees hold: another application's data out of reach, the floor, the safety backup before a restore, a refusal changes nothing.

## Open questions

- The restore's time limit, and whether it differs from a backup item's 30 minutes — the plan (a product owner's choice if it changes what an operator sees).
