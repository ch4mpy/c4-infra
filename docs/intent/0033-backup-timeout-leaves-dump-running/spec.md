# Spec: A demo host backup cut by its time limit may leave its dump running, a restore has no time limit, and four backup paths are untested

- Intent: [0033](intent.md)
- Status: approved
- Version: 1
- Risk: high (rules: the isolation between applications, root stops processes in an application's containers and sessions in its database, and must reach nothing of another's, nor of the application's own; personal data, a restore cut halfway leaves an application's users' data half restored; tech lead's agreement required, the product owner being the tech lead)
- Policies applied: none yet; standing constraints: 0027's spec (RQ-01 to RQ-08, PA-01 to PA-07 as decided) and its review round (its plan, *Deviations*), README "Accounts" and "Backups", 0002 (one root-owned command, the application is the account that runs it), 0007 (nothing of another application's within reach), 0025 (a refused command changes nothing)
- Approved: 2026-10-28, Jérôme Wacongne (product owner, and tech lead: the high risk agreed; in the drafting session; every point of attention decided)

## Summary

A backup item or a restore step that outlasts its time limit is stopped where it runs, in the application's containers and its database too, before `c4-app` says so and frees the application's lock; a restore gets a time limit (PA-01); a nightly run cut after 2 hours cleans up the same way. Stand-in tests then hold the time limits and the three other paths that 0027's review round only read: a `volumes` service without a named volume, a volume shared by a `postgres` and a `volumes` service, and the restart order over several `depends_on` layers. What the operator sees, and who sets the limits: PA-02, PA-03.

## Requirements

- **RQ-01:** A backup item (a database's dump, a volume's copy) that hasn't ended within its time limit (1800 s) is stopped where it runs: the dump's process in the database's container and the database session it opened, a volume copy's throwaway container. The backup is then refused as an item's failure is today. `c4-app` has ended within 60 s of the limit. (intent: expected, proposed outcome)
- **RQ-02:** A restore has a time limit (PA-01) on each step that runs a process for it: reading a file whole, recreating a database, restoring its dump, emptying and refilling a volume (its safety backup is a backup: RQ-01). A step that exceeds it is stopped as RQ-01 says. The restore then fails as 0027's review round decided: before any data was replaced, its containers start again and nothing has changed; after, they stay stopped and the output names the safety backup and the commands that put it back. (intent: proposed outcome)
- **RQ-03:** A nightly run that its limit (7200 s) cuts ends the application's backup as RQ-01 does: what it started is stopped, the containers it stopped run again, nothing of it is kept. This happens within the 60 s before the KILL that follows, and the log says the run was stopped after 7200 s. (intent: expected, whatever limit cuts it)
- **RQ-04:** Once `c4-app` has ended, however a time limit ended it, nothing it started runs on: no process on the host or in a container, no session in a database. Nothing holds the application's lock either: the application's next `c4-app` command doesn't wait. (intent: expected)
- **RQ-05:** Each cut says so in the output, and so in the nightly log: the item or step, its limit, what was stopped. A process or session whose stop `c4-app` can't confirm within the 60 s is named with its container, and the command exits 1. (What the operator sees: PA-02.) (intent: "says so")
- **RQ-06:** Stand-in tests hold the time limits (RQ-01 to RQ-04) and the three other untested paths of 0027's review round: a `volumes` service that mounts no named volume of the project is refused; a volume that a `postgres` and a `volumes` service both mount; the restart order over several `depends_on` layers. Each test fails when the code of its path is removed. (intent: proposed outcome)
- **RQ-07:** README ("Backups"), `c4-app`'s header and usage, and (PA-03 B) `docs/demo-setup.md` say each limit, what a cut stops and says, and who may change a limit. (intent: affected systems; 0027 RQ-08)

## Invariants

- **IV-01:** Another application's data stay out of reach. A stop acts only in the containers `c4-app` selected for the application (0027 RQ-06: compose's project label and the name), and only on the processes and database sessions it started there. It never stops a process or a session of the application's own, nor anything of another application's. (0007; 0027 RQ-06)
- **IV-02:** The floor holds as it is: each item is written up to the room above it, refused under it (0027 PA-05 B and its review round; 0027's AC-08 test still proves it).
- **IV-03:** The safety backup comes first: a restore replaces nothing before the backup of the state before is complete, and a restore cut once it has begun names that backup (0027 PA-06 A).
- **IV-04:** A refusal changes nothing. A cut backup keeps no `.partial` and no stamp, removes no earlier backup (no rotation after a failure), and leaves the containers it stopped running. A restore cut before it replaced any data leaves the data and the running containers as they were.
- **IV-05:** No value the application writes sets a limit or reaches root's shell: the limits come from `c4-app`, or (PA-03 B) from a root-only setting, never from the application's files, labels or environment.

## Out of scope

- The values of a backup item's limit (1800 s) and a nightly run's (7200 s): unchanged (PA-03 says who may change them).
- An interruption other than a time limit (Ctrl-C at the operator's terminal, a lost connection, a host restart): as today.
- 0027's other "Details left" (`tar -t` and a cut at a member boundary, the `sudo c4-app up` advised after a failed restore, compose's version on the demo host).
- Keycloak's backup (`demo/backup.sh:23`, no limit either).

## Design

### Current behaviour

At `main` 62ef9b2. Everything below was read in the code and the documentation; none of it has been reproduced.

- **The limits.** `ITEM_TIMEOUT=1800` (`demo/c4-app:508`) bounds each item as `timeout "$ITEM_TIMEOUT" <docker CLI> | head -c` (`:658`), with no `--kill-after`; a status of 124 is refused (`:664`). `NIGHTLY_TIMEOUT=7200` bounds each application's nightly run with `--kill-after=60` (`:127`, `:144-147`). A restore has no limit on any of its steps: reading each file whole (`:858`, `:862`), recreating each database (`:908-910`), restoring its dump (`:911`), refilling each volume (`:918-920`). Only its safety backup (`:904`, a backup) and the restart (300 s per layer, `:703`) are bounded. A stuck restore holds the lock (`:190-194`): the application's `up` and its nightly backup wait 600 s, then fail.
- **A dump that is cut** (`:767`). `timeout` ends the `docker exec` CLI only. `docker exec` has no `--sig-proxy`, unlike `docker run` (docs.docker.com, `docker container exec`), and no API ends an exec'd process (moby/moby#9098, open: "Terminating a running 'exec' session via an API has not been implemented yet"). So `pg_dump` may run on in the database's container, and its session holds an `ACCESS SHARE` lock on each table it has dumped until the dump ends. A migration's `ALTER TABLE` waits behind that lock, and every later query on the table waits behind the migration. The server notices a dead client only when it next sends to or reads from it (`client_connection_check_interval`, default 0, PostgreSQL 18). A dump still waiting for a lock goes on waiting, up to `--lock-wait-timeout=120s` (`:503`). Meanwhile `c4-app` has refused, removed the `.partial` and freed its lock (`leave`, `:202-214`).
- **A volume's copy that is cut** (`:775`). `docker run` passes the signal on to `tar` (`--sig-proxy`, default true). `tar` is the container's PID 1, which "ignores any signal with the default action" (docs, `docker run`). So `tar` and the CLI may run on, and `timeout`, having no `--kill-after`, waits for them: the 1800 s don't bound a volume's copy, and the containers that mount the volume stay stopped meanwhile.
- **A nightly run that is cut.** GNU `timeout` signals its own process group (coreutils, `--foreground`). That group holds `runuser`, `sudo` and `c4-app`, but not the item's `timeout` and its CLI, which are in a group of their own. Bash runs `c4-app`'s TERM trap (`:217`) only once the running command ends (bash manual, "Signals"). If that command is still running 60 s later, the KILL ends `c4-app` without `leave`. The containers a volume item stopped then stay stopped. The processes left running inherit the lock's descriptor (`exec 9>`, `:190`), so they hold the application's lock after `c4-app` has ended.
- **What no test covers** (0027's plan, *Verification*, "Details left").
  - The time limits: `grep` finds no 1800, no 7200 and no `didn't end within` in `tests/`.
  - A `volumes` service that mounts no named volume: refused (`:610-611`).
  - A volume shared by a `postgres` and a `volumes` service: archived once, under the first `volumes` service (`:614-628`), and every running container that mounts it, the database included, stopped meanwhile (`:683-699`).
  - The restart in `depends_on` layers, read from compose's label (`:719-753`). `tests/fixtures/0027/data.yml` has no `depends_on`, and fact (b) measured `compose start`, which `c4-app` no longer runs.
- **For the plan**: the official `postgres` image (`debian:trixie-slim`) has coreutils' `timeout` but no `procps` (docker-library/postgres, `18/trixie/Dockerfile`); root on the host sees a container's processes (`docker top`); `pg_terminate_backend` ends a session of the caller's own role (a superuser's only for a superuser, PostgreSQL 18).

### Behaviour per persona

- **Application**: when a time limit cuts its backup or restore, nothing of that command keeps running. No dump keeps a lock on its database, so a migration that follows isn't blocked. Its containers run again (a backup; a restore cut before it replaced any data) or stay stopped with the commands to put the data back (a restore cut after it began). Its next `c4-app` command runs at once. Its workflow sees the cut in the output, and exit 1.
- **Demo operator**: the nightly log says which item or step was cut, after how long, and what was stopped, or names a container where a stop couldn't be confirmed. The README gives the restore's limit; PA-03 says who may change a limit.

### API and contracts

```text
sudo c4-app backup                  an item over 1800 s: stopped where it runs, then refused; c4-app ends within 60 s of the limit
sudo c4-app restore <stamp> --yes   a step over PA-01's limit: stopped, then the restore fails as 0027's (before or after replacing data)
c4-app nightly                      an application's run over 7200 s: its backup stopped as above, its log "== exit <n>: stopped after 7200 s"
```

- Messages: `c4-app: <file> didn't end within <n> s: stopped (<what>), no backup of <app> kept` (`:664`'s, which now names what was stopped); `c4-app: restore of backup <stamp>: <step> didn't end within <n> s: stopped (<what>)`, then 0027's message for a failed restore; `c4-app: <what> in <container> didn't stop within 60 s` (exit 1).
- (PA-03 B) Limits: one value per kind of limit (backup item, restore step, nightly run), in seconds, digits only, read by `c4-app` from a root-only file on the host; the defaults apply when the file is absent.

### User interface

None.

### Data

None new; the backups are unchanged.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| 0002: one root-owned command, the application is the account that runs it | unchanged: the stop is `c4-app`'s, for the application read from `SUDO_USER` |
| 0007, 0027 RQ-06: nothing of another application's, containers matched by the project's label and name, no application value in root's shell | IV-01, IV-05, AC-06 |
| 0027 PA-05 B: the floor | IV-02 |
| 0027 PA-06 A and its review round: the safety backup first; a restore that fails once it has begun leaves the containers stopped and names it | IV-03, RQ-02, AC-03 |
| 0027 PA-04 A and its review round: rotation only after a success | IV-04 |
| 0025, 0027 RQ-02: backup and restore stage nothing, pull nothing | unchanged |

## Points of attention

### PA-01: The restore's time limit

- Issue: today a restore has none. One stuck step holds the application's lock, and, once it has begun replacing data, keeps its containers stopped until someone notices. A cut restore costs more than a cut backup: once it has begun, the application stays stopped on half-restored data until a second restore (0027's review round). And `pg_restore` rebuilds indexes and constraints that `pg_dump` only reads, so a restore is slower than the dump it restores.
- Options: A each step bounded like a backup item, 1800 s / B each step bounded at 3600 s, twice a backup item's limit / C one limit for the whole restore, 7200 s like a nightly run (its safety backup's items keeping 1800 s each)
- Recommendation: B. The limit should stop a step that is stuck, not one that is slower than its backup's dump: a backup taken within its limit can then be restored within this one. Per step, the limit doesn't depend on how many items a project declares. The safety backup keeps a backup item's 1800 s, since it is one.
- Decides: PO, tech lead
- Decision: B, as recommended — Jérôme Wacongne (product owner, tech lead), 2026-10-28

### PA-02: What the operator sees when a time limit cuts a backup or a restore

- Issue: a cut is a failure that an operator should be able to tell apart from a refusal (a label, the floor), and the nightly run's only trace is its log.
- Options: A one line in the command's output, and so in the nightly log and the workflow's log: the item or step, its limit, what was stopped; exit 1, as any refusal / B A, plus a status of its own for a cut (124, as `timeout`), so a workflow can tell a time limit from a refusal / C A, plus a mark outside the log (e.g. `sudo c4-app restore`'s listing saying the last backup was cut)
- Recommendation: A. The operator already reads the nightly log (0027 PA-02), and a workflow shows the output. One exit status for every failure keeps 0027's contract. Watching the nightly runs from outside would be an intent of its own.
- Decides: PO
- Decision: A, as recommended — Jérôme Wacongne (product owner, tech lead), 2026-10-28

### PA-03: Who may change the time limits

- Issue: the limits are constants of `c4-app`, the same for every application. A large volume (immo's uploaded files) may need more. A test can't wait 30 minutes, so it needs shorter limits. Whatever sets a limit is read by root.
- Options: A fixed in `c4-app`: changing one means changing c4-infra, and the tests run a copy with shorter constants, installed in the stand-in only (so the proof runs a variant of the code it proves) / B host-wide, from a root-only file (digits only, the defaults when it is absent), which the operator edits from `ubuntu` and the tests write: one value per kind of limit, for every application / C per application: B's file with one line per application, or a registry column (as 0027 PA-04 C)
- Recommendation: B. The tests prove the very code that runs on the host. The operator can give a slow night more time without a release. Nothing the application writes sets a limit (IV-05). Per-application limits (C) can wait for an application whose data needs one: none uses the backups yet.
- Decides: PO, tech lead
- Decision: B, as recommended — Jérôme Wacongne (product owner, tech lead), 2026-10-28

## Acceptance criteria

The stand-in tests below shorten the limits as PA-03 decides.

- **AC-01:** Given Faito on the stand-in with `data.yml`, and a session of Faito's own holding an `ACCESS EXCLUSIVE` lock on a table, when `sudo c4-app backup` runs, then it ends within the item's limit plus 60 s, refused, naming `db.dump` and the limit; `faito.db` runs no `pg_dump` (`docker top`) and `pg_stat_activity` holds no session of the dump, Faito's own session still there; no stamp, no `.partial`; once that session ends, the next `sudo c4-app backup` doesn't wait and succeeds. The test fails on the code before the change. (RQ-01, RQ-04, RQ-05, IV-01, IV-04)
- **AC-02:** Given a volume's copy that outlasts the item's limit (its throwaway container held by the test), when the backup runs, then it ends within the limit plus 60 s, refused, naming the archive and the limit. No throwaway container is left, `faito.files` runs again, nothing is kept, and the next command doesn't wait. (RQ-01, RQ-04, IV-04)
- **AC-03:** Given a backup of Faito, and a restore of it whose volume refill outlasts the restore's limit (PA-01), when `sudo c4-app restore <stamp> --yes` runs, then it ends within the limit plus 60 s, naming the step and the limit; no throwaway container is left; `faito.files` and `faito.other` stay stopped, `faito.db` runs; the output names the safety backup, and restoring it, then `sudo c4-app up`, brings the rows, the files and the containers back. (RQ-02, RQ-04, IV-03)
- **AC-04:** Given a restore whose reading of a file whole outlasts the limit, when it runs, then it is refused, naming the step, and nothing has changed: the rows, the files, the backups (no safety backup taken), the containers (`StartedAt`). (RQ-02, IV-04)
- **AC-05:** Given a nightly limit shorter than an item's, and a volume's copy of Faito that outlasts it, when root's `c4-app nightly` runs, then Faito's log says the run was stopped after that limit, Faito's containers run, no throwaway container and no `.partial` are left, and the next `sudo c4-app backup` doesn't wait. (RQ-03, RQ-04)
- **AC-06:** Given Hurura'a on the same stand-in, with a session of its own open on its database, when Faito's dump is cut (AC-01), then Hurura'a's containers (`StartedAt`) and that session are unchanged. (IV-01)
- **AC-07:** Given a service labelled `volumes` that mounts no named volume of the project, when `sudo c4-app backup` runs, then it is refused, naming the service: nothing is written and no container is stopped. A restore of an earlier backup is refused the same way, and nothing changes. (RQ-06)
- **AC-08:** Given a volume that a `postgres` service and a `volumes` service both mount, when a backup then a restore run, then the backup holds the dump and that volume's archive once, under the `volumes` service; both containers were stopped during the copy (`StartedAt` changed) and run again; the restore brings back the dump's rows and the volume's files, every container running. (RQ-06)
- **AC-09:** Given services in three `depends_on` layers (each `service_healthy` on the previous one, each healthy seconds after its start) that a restore stops, when they start again, then each starts only once the one it depends on is healthy (`StartedAt` against health), and all of them run. (RQ-06)
- **AC-10:** Given the README, `c4-app`'s usage and (PA-03 B) `docs/demo-setup.md`, then they name each limit, the restore's included, what a cut stops and says, and who may change a limit. (RQ-07)

## Intent questions

- The restore's time limit, and whether it differs from a backup item's 30 minutes → PA-01. It changes what the operator reads: the README and the usage name it (RQ-07).
- "Observed: not reproduced yet" → read in the code and the documentation (*Current behaviour*); AC-01 reproduces it, since its test fails on the code before the change.

## Change log

- v1 — 2026-10-28 — first version. The intent was accepted as a bug with "Spec needed: no"; the product owner then asked for a spec, and this spec's commit sets that field to yes.
- v1 — 2026-10-28 — approved by the product owner and tech lead in the drafting session: PA-01 B, PA-02 A, PA-03 B, as recommended.
