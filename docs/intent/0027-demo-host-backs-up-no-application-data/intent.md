# Intent: The demo host backs up no application's data

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: change
- Source: conversation (the alignment analyses of Tickee and poc-immo-pf on c4-infra, 2026-10-28)
- Spec needed: yes
- Status: accepted
- Opened: 2026-10-28
- Decided: 2026-10-28
- Supersedes: —
- Mode: bootstrap

## Problem

c4-infra backs up Keycloak's database every night (`demo/backup.sh`). An application's account runs no `docker` command, so nothing backs up its databases or volumes (Tickee's database and its tenant2 directory, immo's), and nothing restores them: `docs/migration.md` ("`deploy/backup.sh`") says to open an intent for it.

## Proposed outcome

An application's data on the demo host (its databases, its volumes) is backed up and can be restored, from its account, without the `docker` group.

## Affected users and systems

- Personas: Application (Tickee, immo); Demo operator
- Modules / systems: demo host (`demo/c4-app`, `demo/backup.sh`)

## Constraints

- 0002 and 0007 hold: no `docker` group for an application's account, one root-owned command, nothing of another application's within reach.

## Open questions

- What is backed up (a database's dump, a volume's files), where it is kept and how long, who triggers it (the nightly cron, `sudo c4-app backup`), how a restore runs — the spec.
