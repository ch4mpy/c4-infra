# Spec: The demo host backs up no application's data

- Intent: [0027](intent.md)
- Status: draft
- Version: 1
- Risk: high (rules: personal data, the backups hold what every application's demo users entered; the isolation between applications, root reads and writes an application's databases and volumes on the one Docker daemon; authorization, two more commands the applications' accounts run as root; tech lead's agreement required)
- Policies applied: none yet; standing constraints: README "Accounts" and "Backups", 0002 (no `docker` group for an application's account, one root-owned command, the application is the account that runs it), 0007 (nothing of another application's within reach), 0011's accepted risk (a leaked deployment key is not contained), 0025 (accepted: a refused deployment leaves the running files as they were)
- Approved: —

## Summary

Two more commands of `c4-app`, from an application's account: `sudo c4-app backup` saves the data its compose project declares (a database's logical dump through its own tool, a service's named volumes) into a backup directory of its own on the host, and `sudo c4-app restore <stamp>` puts one back into the running project. The host backs up every application each night, keeps backups a bounded time, and no application reaches another's. Keycloak's backup is unchanged. What is declared, who triggers, who reads, how long, the disk, the restore's safety and an off-host copy are the product owner's choices (PA-01 to PA-07).

## Requirements

- **RQ-01:** `sudo c4-app backup`, from an application's account, writes one backup of the data its compose project declares (PA-01): each declared database dumped hot through its own container's tool; each declared service's named volumes copied with that service stopped, then started again. A project that declares nothing, or isn't running, is named and nothing is written. (intent: outcome)
- **RQ-02:** The backup acts on what runs: the declaration is read from the project's containers as `sudo c4-app up` last created them, never from `~/<app>/`, which may hold a deployment not done yet or refused; backup and restore stage nothing and pull nothing. (intent: constraint; 0025)
- **RQ-03:** The host backs up every application that has an account each night, after Keycloak's 03:15, by running RQ-01 as that account; each run's output goes to a log the operator reads (PA-02). (intent: open question, who triggers it)
- **RQ-04:** A backup is a directory named by its stamp in the application's own backup directory, outside `/var/lib/c4-apps/` and anything a container may mount, unreadable by any other application's account (who reads it: PA-03); older backups are removed as PA-04 decides; the disk is guarded as PA-05 decides. (intent: open question, where and how long)
- **RQ-05:** `sudo c4-app restore <stamp>` restores one backup of the application's own, named by its stamp, never a path: each database recreated empty then its dump restored, each volume emptied then its files put back; the project then runs again. Its safety: PA-06. (intent: outcome, restored from its account)
- **RQ-06:** Backup and restore touch only the containers and volumes of the application's own compose project, matched by the project's label (`com.docker.compose.project=<app>`) and by the name its rules give (`<app>.` or `<app>-` for a container, `<app>_` for a volume), whatever labels its compose file sets; root reads or writes a volume's files only through a throwaway container of an image of the stack, on no network, mounting that volume and that backup's directory only; no value the application declares reaches root's shell (a kind from a fixed list; a database's user and name read inside its container). (intent: constraint, 0002 and 0007)
- **RQ-07:** Backup and restore wait for the application's other `c4-app` commands, as `up` does; a refusal names the service, volume or stamp, and changes nothing. (intent: constraint)
- **RQ-08:** README ("Accounts", "Backups"), `c4-app`'s header and usage, `docs/migration.md` (its step on `deploy/backup.sh`) and `docs/demo-setup.md` say how an application declares, triggers, finds and restores its backups. (intent: affected systems)

## Out of scope

- Keycloak's backup and restore (`demo/backup.sh`, README "Backups"): unchanged; every application's realm users are there already.
- A workstation: a developer's data is their own.
- A logical dump for another engine (MySQL, OpenLDAP's `slapcat`, an object store's API): a later intent; their volumes are copied cold (PA-01).
- Removing an application's backups when it leaves the host: the operator's, by hand.
- 0025 (the staging copy) and 0026 (the containers' logs), which change `c4-app` too.

## Design

### Current behaviour

- `demo/backup.sh:22-25`, from the `c4-infra` account's crontab at 03:15 (`demo/deploy.sh:69-74`): a hot `pg_dump -Fc` of Keycloak's database through `docker compose exec`, into `~/backups/` (mode 0700, `:15`), nightly dumps kept 7 days (`:25`), `--before-upgrade` ones until removed by hand (`:17-20`). Its header and the README say "Each application backs up its own databases" (`backup.sh:3-4`, `README.md:711-712`).
- An application's account is outside `docker`, its one sudo rule is `c4-app` (`demo/vps-bootstrap.sh:102`, `:164`); `c4-app` has `pull`, `up`, `down`, `register` (`demo/c4-app:87-96`, `:371-390`), none of which reads a database or a volume; `docs/migration.md:238-240` says to open an intent. Tickee's own `deploy/backup.sh` runs `docker compose` as its account: impossible there.
- An application's data can only be in its project's named volumes: named `<app>_<key>`, local driver, never external (`c4-app:212-217`), any bind mount read-only (`:251-255`). Tickee: `rest-api-db` (PostgreSQL 18, `rest_api_data`) and its tenant2 directory `ldap2` (OpenLDAP, `ldap2_data`, `ldap2_config`; its current script skips it: read-only, rebuilt from `ldap/*.ldif`). immo: `rest_api_db` (PostgreSQL 18, `rest_api_data`) and `rustfs` (`rustfs_data`, uploaded files). Both databases set `POSTGRES_USER` and `POSTGRES_DB`.
- A service's `labels` pass the allowlist (`c4-app:189`); a volume's aren't checked (`:212-217`).
- `c4-app` runs one command at a time per application (`:122-125`). Every staging removes the root-only snapshot, `register`'s included (`:134`): the model `up` checked isn't always on disk afterwards.
- The firewall rejects every new outgoing connection of the `c4-apps` group but on the loopback (`vps-bootstrap.sh:125`): an application's account can't send a backup off the host; one can be pulled through its key (inbound, as its rsync).
- The demo host isn't set up yet (`README.md:554`): no data to migrate.

### Behaviour per persona

- **Application**: declares in its `compose.yml` the services that hold its data (PA-01); is backed up each night with no step of its own, and may run `sudo c4-app backup` from its workflow before a deployment that migrates its database (PA-02); reads or downloads its backups (PA-03); restores one from its account (PA-06).
- **Demo operator**: nothing to schedule beyond `vps-bootstrap.sh` (PA-02); reads the nightly log; watches the disk (PA-05); an off-host copy is theirs (PA-07); removes a departed application's backups.

### API and contracts

```text
compose.yml, on a service that holds data (PA-01 B):
  labels:
    c4-infra.backup: postgres   logical dump, hot: pg_dump -Fc in the container, as its POSTGRES_USER, of its POSTGRES_DB
    c4-infra.backup: volumes    the service's named volumes, the service stopped meanwhile

sudo c4-app backup                  /var/backups/c4-apps/<app>/<stamp>/: <service>.dump, <service>.<volume>.tar
sudo c4-app restore                 lists the stamps, restores nothing
sudo c4-app restore <stamp> --yes   (PA-06 A) backs up the current state, then restores <stamp>
```

- Messages: `c4-app: backup <stamp> of <app>: <file> (<size>), …`; `c4-app: <app> declares no data to back up (label c4-infra.backup on a service: postgres or volumes)`; `c4-app: service <s>: c4-infra.backup '<value>': postgres or volumes`; `c4-app: no backup <stamp> of <app>`.
- `/var/backups/c4-apps/<app>/`: root-owned, its mode PA-03's; outside `/var/lib/c4-apps/` (its `.run.<app>` and `.<app>.lock` namespace), which a container may mount only under `<app>/`. The nightly log: `/var/backups/c4-apps/<app>/backup.log`.

### User interface

None.

### Data

The backups: dumps and archives of each application's databases and volumes, its users' personal data included, on the host, for PA-04's time.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| 0002: no `docker` group, one root-owned command, the application is the account that runs it | backup and restore are `c4-app` commands, the application read from `SUDO_USER`; the nightly schedule runs them as each account (PA-02) |
| 0007: nothing of another application's within reach | RQ-06, AC-03; the backups outside anything a container may mount (RQ-04) |
| 0011's accepted risk: a leaked deployment key isn't contained | unchanged; such a key can restore an older backup (the state before kept, PA-06 A), not change or delete one (PA-03 A or B) |
| 0025: a refused deployment leaves the running files as they were | RQ-02: backup and restore stage nothing |
| README "Backups": Keycloak's dump, kept 7 days | unchanged; the applications' rotation is PA-04's |

## Points of attention

### PA-01: What is backed up, declared how

- Issue: a logical dump runs hot and restores into a newer PostgreSQL, but needs a tool per engine; a volume's files fit any store (OpenLDAP, RustFS) but only cold, and a PostgreSQL's files restore into the same major version only. Tickee's directory is rebuilt from its LDIF files; immo's object store holds uploaded files.
- Options: A every named volume of the project, cold (the project stopped meanwhile): nothing to declare / B declared per service by a label (API and contracts): `postgres` dumped hot, `volumes` copied cold, the rest not backed up / C B, plus every named volume no label declares, cold (`c4-infra.backup: none` leaves one out)
- Recommendation: B: the databases stay up and their dumps survive an upgrade, the application says what matters (Tickee's directory or not), a label passes today's allowlist; each run names the volumes it left out, so a forgotten one shows.
- Decides: PO
- Decision: to decide

### PA-02: Who triggers a backup

- Issue: the `c4-infra` account can't run `c4-app` (its one sudo rule installs it, `vps-bootstrap.sh:103`); an application's workflow can install a crontab (Tickee's does today); a deployment that migrates its database wants a way back first, as Keycloak's `--before-upgrade`.
- Options: A on demand only, `sudo c4-app backup`, scheduled by the application's own crontab if it wants / B the host only: a root-owned nightly schedule installed by `vps-bootstrap.sh`, running the backup as each application's account (03:45) / C both
- Recommendation: C: no application goes without a backup for a missing step, and each can take its way back before a risky deployment.
- Decides: PO
- Decision: to decide

### PA-03: Where backups are kept, and who reads them

- Issue: the account already reaches its data (its containers, its `.env`): reading its backups exposes nothing new. Writing them does: a leaked key (0011's risk) that can change or delete them takes the way back with the data, and a restore would feed root's tools a file the application wrote; root writing into a directory the application owns invites a planted link.
- Options: A `/var/backups/c4-apps/<app>/`, root only (0700): the application restores through `c4-app`, can't read, copy or delete its backups / B the same, `0750 root:<app>` as its staging copy: it reads and downloads them, can't change or delete them / C in its home, written as the application: it reads, copies and deletes them
- Recommendation: B: the application gets its own data, off the host too if it wants (PA-07 B), and a restore reads only what root wrote.
- Decides: tech lead
- Decision: to decide

### PA-04: How long backups are kept

- Issue: they hold personal data that an erasure (immo's account deletion) doesn't reach until they're gone; under PA-03 A or B the application can't remove one, so whatever isn't rotated stays until the operator removes it.
- Options: A 7 days for every backup, nightly or on demand, as Keycloak's nightly ones / B 7 days for the nightly ones, on-demand and pre-restore ones until the operator removes them, as Keycloak's `--before-upgrade` / C a length per application, a registry column (0004)
- Recommendation: A: one rule, a known bound on how long an erased user's data lasts, nothing piling up that only root can delete.
- Decides: PO
- Decision: to decide

### PA-05: Disk space

- Issue: uploaded files (immo's RustFS) times seven backups can fill the host's one disk, and stop every application's database and Keycloak's with it (0026 raises the same for logs); the VPS's disk isn't known yet.
- Options: A no guard: the operator watches the disk / B a backup is refused, what it wrote removed and named in the log, when the disk's free space falls under a floor (10 % or 5 GB), earlier backups kept / C B, plus a size cap per application
- Recommendation: B: one application's data can't stop the others, for one check per item.
- Decides: tech lead
- Decision: to decide

### PA-06: How a restore protects the running data

- Issue: a restore replaces the running data, and an API writing meanwhile spoils it; the workflows' keys open no terminal (`restrict`), so an interactive confirmation reaches only the operator (`sudo -iu <app>` from `ubuntu`).
- Options: A `sudo c4-app restore <stamp> --yes`: stops the project's containers (a database's alone runs while its dump is restored), backs up the current state first, restores every item of that backup, starts the containers again; refused without `--yes` / B the same with the application's name typed instead of `--yes`: a terminal only, so the operator's / C no command: a README procedure the operator runs as root
- Recommendation: A: the intent wants a restore from the account (C isn't), its workflows have no terminal (B is the operator's only), and the backup taken first undoes a wrong restore.
- Decides: PO, tech lead
- Decision: to decide

### PA-07: A copy off the host

- Issue: on the host only, a lost VPS loses every application's data with its backups, as Keycloak's today; a copy elsewhere puts personal data at a third party, and pushing it needs a secret and an outgoing connection the applications' accounts are denied.
- Options: A none from c4-infra, documented; the operator may take the provider's VPS backups / B A, and an application may pull its own through its key (needs PA-03 B) / C c4-infra copies every backup to an external store (a new secret, an outgoing path)
- Recommendation: B: demo data, no new secret or path; C is a later intent if the demo ever holds data worth it.
- Decides: PO
- Decision: to decide

## Acceptance criteria

- **AC-01:** Given an application on the stand-in demo host whose project declares a PostgreSQL service and a service with volumes (PA-01), when `sudo c4-app backup` runs from its account, then a new stamp holds the dump and the volumes' archives, the database answered throughout, and the volume service runs again. (RQ-01)
- **AC-02:** Given that backup, then rows and files changed, when `sudo c4-app restore <stamp>` runs from the account (PA-06), then the rows and files are the backup's, the project runs, and a backup of the state before the restore exists. (RQ-05)
- **AC-03:** Given applications A and B on the stand-in, A's compose labelling a service and a volume with B's project, when A backs up and restores, then none of B's containers stops, B's volumes and backups are unchanged, A's account can't read B's backup directory, and A's restore refuses B's stamp, a path and `..`. (RQ-04, RQ-06)
- **AC-04:** Given a running project and a new `compose.yml` in `~/<app>/`, not deployed or refused, when its backup runs, then it backs up the services that run, and `/var/lib/c4-apps/<app>/` is unchanged. (RQ-02)
- **AC-05:** Given a label `c4-infra.backup` with another value (`rsync`, `postgres;id`), when the backup runs, then it is refused, naming the service and the value, and nothing is written. (RQ-06, RQ-07)
- **AC-06:** Given two application accounts on the stand-in, when the nightly schedule's command runs, then each running project is backed up, one that declares nothing or isn't running is named in its log, and a backup older than PA-04's limit is removed. (RQ-03, RQ-04)
- **AC-07:** Given `sudo c4-app up` running for an application, when its backup starts, then it waits for `up` to end. (RQ-07)
- **AC-08:** Given free space under PA-05's floor, when a backup runs, then it is refused, named in the log, and earlier backups stay. (RQ-04)
- **AC-09:** Given the README, `c4-app`'s usage, `docs/migration.md` and `docs/demo-setup.md`, then they name the declaration, the commands, the directory, the schedule and the restore, and `docs/migration.md` no longer sends to an intent. (RQ-08)

## Intent questions

- What is backed up (a database's dump, a volume's files)? → PA-01.
- Where it is kept, and how long? → PA-03, PA-04; the disk → PA-05.
- Who triggers it (the nightly cron, `sudo c4-app backup`)? → PA-02.
- How a restore runs? → RQ-05; its safety → PA-06.
- Constraint "0002 and 0007 hold" → RQ-06, AC-03: the account stays outside `docker`, both commands are `c4-app`'s.

## Change log

- v1 — 2026-10-28 — first version
